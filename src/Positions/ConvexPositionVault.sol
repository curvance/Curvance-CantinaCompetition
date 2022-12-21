// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BasePositionVault, ERC4626, SafeTransferLib, ERC20, Math, PriceRouter } from "src/Positions/BasePositionVault.sol";

// External interfaces
import { IBooster } from "src/interfaces/Convex/IBooster.sol";
import { IBaseRewardPool } from "src/interfaces/Convex/IBaseRewardPool.sol";
import { ICurveFi } from "src/interfaces/Curve/ICurveFi.sol";
import { ICurveSwaps } from "src/interfaces/Curve/ICurveSwaps.sol";

// Chainlink interfaces
import { KeeperCompatibleInterface } from "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";
import { AggregatorV2V3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";
import { IChainlinkAggregator } from "src/interfaces/IChainlinkAggregator.sol";

import { console } from "@forge-std/Test.sol"; // TODO remove this

// TODO what contract should act like the Registry in this ecosystem.
// TODO what would happen to reward tokens that are added later, and dont have swap info? Ideally they just sit in here until we add the swap info.
contract ConvexPositionVault is BasePositionVault {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    constructor(
        ERC20 _asset,
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) BasePositionVault(_asset, _name, _symbol, _decimals) {}

    /*//////////////////////////////////////////////////////////////
                          INTERNAL POSITION LOGIC
    //////////////////////////////////////////////////////////////*/

    // Should be set during initialization of clone.
    /**
     * @notice Curve registry exchange contract.
     */
    ICurveSwaps public curveRegistryExchange; // 0x81C46fECa27B31F3ADC2b91eE4be9717d1cd3DD7
    uint256 public pid;
    IBaseRewardPool public rewarder;
    IBooster private booster = IBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    ERC20 private constant WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    ERC20 private constant CVX = ERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    ERC20 private constant CRV = ERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);

    struct CurveDepositParams {
        ERC20 targetAsset;
        uint8 coinsLength;
        uint8 targetIndex;
        bool useUnderlying;
        address pool;
    }

    CurveDepositParams private depositParams;

    // So we store the swap path from each reward token to ETH.
    // Then store a swap path from ETH to the final token we need.

    struct CurveSwapParams {
        address[9] route;
        uint256[3][4] swapParams;
        ERC20 assetIn;
        uint96 minUSDValueToSwap;
    }

    // Stores swapping information to go from an arbitrary reward token to ETH.
    mapping(ERC20 => CurveSwapParams) public arbitraryToETH;

    // Stores swapping information to go from ETH to target token to supply liquidity on Curve
    mapping(ERC20 => CurveSwapParams) public ethToTarget;

    // Owner needs to be able to set swap paths, deposit data, fee, fee accumulator
    uint64 harvestSlippage = 0.1e18;

    function initialize(
        ERC20 _asset,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint64 _platformFee,
        address _feeAccumulator,
        PriceRouter _priceRouter,
        bytes memory _initializeData
    ) external override initializer {
        asset = _asset;
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        platformFee = _platformFee;
        feeAccumulator = _feeAccumulator;
        priceRouter = _priceRouter;
        (
            uint256 _pid,
            IBaseRewardPool _rewarder,
            IBooster _booster,
            CurveDepositParams memory _depositParams,
            ICurveSwaps _curveSwaps,
            CurveSwapParams[] memory swapsToETH,
            ERC20[] memory assetsToETH,
            CurveSwapParams[] memory swapsFromETH,
            ERC20[] memory assetsFromETH
        ) = abi.decode(
                _initializeData,
                (
                    uint256,
                    IBaseRewardPool,
                    IBooster,
                    CurveDepositParams,
                    ICurveSwaps,
                    CurveSwapParams[],
                    ERC20[],
                    CurveSwapParams[],
                    ERC20[]
                )
            );
        pid = _pid;
        rewarder = _rewarder;
        booster = _booster;
        depositParams = _depositParams;
        curveRegistryExchange = _curveSwaps;

        // TODO check for length mismatches.
        for (uint256 i; i < swapsToETH.length; ++i) {
            arbitraryToETH[assetsToETH[i]] = swapsToETH[i];
        }

        for (uint256 i; i < swapsFromETH.length; ++i) {
            ethToTarget[assetsFromETH[i]] = swapsFromETH[i];
        }
    }

    function _withdraw(uint256 assets) internal override {
        IBaseRewardPool rewardPool = IBaseRewardPool(rewarder);
        rewardPool.withdrawAndUnwrap(assets, false);
    }

    function _deposit(uint256 assets) internal override {
        asset.safeApprove(address(booster), assets);
        booster.deposit(pid, assets, true);
    }

    function harvest() public override returns (uint256 yield) {
        uint256 pending = _calculatePendingRewards();
        if (pending > 0) {
            // We need to claim vested rewards.
            _vestRewards(_totalAssets + pending);
        }

        // Can only harvest is previous reward period is done.
        if (_lastVestClaim >= _vestingPeriodEnd) {
            // Harvest convex position.
            rewarder.getReward(address(this), true);

            // Save token balances
            uint256 rewardTokenCount = 2 + rewarder.extraRewardsLength();
            ERC20[] memory rewardTokens = new ERC20[](rewardTokenCount);
            rewardTokens[0] = CRV;
            rewardTokens[1] = CVX;
            uint256[] memory rewardBalances = new uint256[](rewardTokenCount);
            rewardBalances[0] = CRV.balanceOf(address(this));
            rewardBalances[1] = CVX.balanceOf(address(this));
            for (uint256 i = 2; i < rewardTokenCount; i++) {
                rewardTokens[i] = ERC20(rewarder.extraRewards(i - 2));
                rewardBalances[i] = rewardTokens[i].balanceOf(address(this));
            }

            uint256 valueIn;
            uint256 ethOut;
            address[4] memory pools;
            for (uint256 i = 0; i < rewardTokenCount; i++) {
                // Take platform fee
                uint256 fee = rewardBalances[i].mulDivDown(platformFee, 1e18);
                rewardBalances[i] -= fee;
                rewardTokens[i].safeTransfer(feeAccumulator, fee);
                // Get the reward token value in USD.
                uint256 valueInUSD = rewardBalances[i].mulDivDown(
                    priceRouter.getPriceInUSD(rewardTokens[i]),
                    10**rewardTokens[i].decimals()
                );
                CurveSwapParams memory swapParams = arbitraryToETH[rewardTokens[i]];
                // Check if value is enough to warrant a swap.
                if (valueInUSD >= swapParams.minUSDValueToSwap) {
                    valueIn += valueInUSD;
                    // Perform Swap into ETH.
                    rewardTokens[i].safeApprove(address(curveRegistryExchange), rewardBalances[i]);
                    ethOut += curveRegistryExchange.exchange_multiple(
                        swapParams.route,
                        swapParams.swapParams,
                        rewardBalances[i],
                        0,
                        pools,
                        address(this)
                    );
                }
            }
            // Take upkeep fee.
            uint256 fee = ethOut.mulDivDown(upkeepFee, 1e18);
            // If watchdog is set, transfer WETH to it otherwise, leave it here.
            if (positionWatchdog != address(0)) WETH.safeTransfer(positionWatchdog, fee);
            ethOut -= fee;

            uint256 assetsOut;
            // Convert assets into targetAsset.
            if (depositParams.targetAsset != WETH) {
                CurveSwapParams memory swapParams = ethToTarget[WETH];
                WETH.safeApprove(address(curveRegistryExchange), ethOut);
                assetsOut = curveRegistryExchange.exchange_multiple(
                    swapParams.route,
                    swapParams.swapParams,
                    ethOut,
                    0,
                    pools,
                    address(this)
                );
            } else assetsOut = ethOut;
            // Compare value in vs value out.
            uint256 valueOut = assetsOut.mulDivDown(
                priceRouter.getPriceInUSD(depositParams.targetAsset),
                10**depositParams.targetAsset.decimals()
            );
            // console.log("Value In", valueIn);
            // console.log("Value Out", valueOut);
            if (valueOut < valueIn.mulDivDown(1e18 - (upkeepFee + harvestSlippage), 1e18)) revert("Bad slippage");

            // Deposit assets to Curve.
            _addLiquidityToCurve(assetsOut);

            // Deposit Assets to Convex.
            yield = asset.balanceOf(address(this));
            _deposit(yield);

            // Update Vesting info.
            _rewardRate = uint128(yield / REWARD_PERIOD);
            _vestingPeriodEnd = uint64(block.timestamp) + REWARD_PERIOD;
            _lastVestClaim = uint64(block.timestamp);
        } else revert("Can not harvest now");
    }

    /**
     * @notice Allows caller to make swaps using the Curve Exchange.
     * @param swapData bytes variable storing the following swap information
     *      address[9] route: array of [initial token, pool, token, pool, token, ...] that specifies the swap route on Curve.
     *      uint256[3][4] swapParams: multidimensional array of [i, j, swap type]
     *          where i and j are the correct values for the n'th pool in `_route` and swap type should be
     *              1 for a stableswap `exchange`,
     *              2 for stableswap `exchange_underlying`,
     *              3 for a cryptoswap `exchange`,
     *              4 for a cryptoswap `exchange_underlying`
            ERC20 assetIn: the asset being swapped
            uint256 assets: the amount of assetIn you want to swap with
     *      uint256 assetsOutMin: the minimum amount of assetOut tokens you want from the swap
     * @param receiver the address assetOut token should be sent to
     * @return amountOut amount of tokens received from the swap
     */
    function swapWithCurve(bytes memory swapData, address receiver) public returns (uint256 amountOut) {
        (
            address[9] memory route,
            uint256[3][4] memory swapParams,
            ERC20 assetIn,
            uint256 assets,
            uint256 assetsOutMin
        ) = abi.decode(swapData, (address[9], uint256[3][4], ERC20, uint256, uint256));

        // Transfer assets to this contract to swap.
        assetIn.safeTransferFrom(msg.sender, address(this), assets);

        address[4] memory pools;

        // Execute the stablecoin swap.
        assetIn.safeApprove(address(curveRegistryExchange), assets);
        amountOut = curveRegistryExchange.exchange_multiple(route, swapParams, assets, assetsOutMin, pools, receiver);
    }

    /**
     * @notice Attempted to deposit into an unsupported Curve Pool.
     */
    error DepositRouter__UnsupportedCurveDeposit();

    function _addLiquidityToCurve(uint256 amount) internal {
        depositParams.targetAsset.safeApprove(depositParams.pool, amount);
        if (depositParams.coinsLength == 2) {
            uint256[2] memory amounts;
            amounts[depositParams.targetIndex] = amount;
            if (depositParams.useUnderlying) {
                ICurveFi(depositParams.pool).add_liquidity(amounts, 0, true);
            } else {
                ICurveFi(depositParams.pool).add_liquidity(amounts, 0);
            }
        } else if (depositParams.coinsLength == 3) {
            uint256[3] memory amounts;
            amounts[depositParams.targetIndex] = amount;
            if (depositParams.useUnderlying) {
                ICurveFi(depositParams.pool).add_liquidity(amounts, 0, true);
            } else {
                ICurveFi(depositParams.pool).add_liquidity(amounts, 0);
            }
        } else if (depositParams.coinsLength == 4) {
            uint256[4] memory amounts;
            amounts[depositParams.targetIndex] = amount;
            if (depositParams.useUnderlying) {
                ICurveFi(depositParams.pool).add_liquidity(amounts, 0, true);
            } else {
                ICurveFi(depositParams.pool).add_liquidity(amounts, 0);
            }
        } else revert DepositRouter__UnsupportedCurveDeposit();
    }
}
