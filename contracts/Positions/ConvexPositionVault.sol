// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import { BasePositionVault, ERC4626, SafeTransferLib, ERC20, Math, PriceRouter } from "contracts/Positions/BasePositionVault.sol";

// External interfaces
import { IBooster } from "contracts/interfaces/Convex/IBooster.sol";
import { IBaseRewardPool } from "contracts/interfaces/Convex/IBaseRewardPool.sol";
import { IRewards } from "contracts/interfaces/Convex/IRewards.sol";
import { ICurveFi } from "contracts/interfaces/Curve/ICurveFi.sol";
import { ICurveSwaps } from "contracts/interfaces/Curve/ICurveSwaps.sol";

// Chainlink interfaces
import { KeeperCompatibleInterface } from "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";
import { AggregatorV2V3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";
import { IChainlinkAggregator } from "contracts/interfaces/IChainlinkAggregator.sol";

contract ConvexPositionVault is BasePositionVault {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    /*//////////////////////////////////////////////////////////////
                             STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct CurveDepositParams {
        ERC20 targetAsset;
        uint8 coinsLength;
        uint8 targetIndex;
        bool useUnderlying;
        address pool;
    }

    struct CurveSwapParams {
        address[9] route;
        uint256[3][4] swapParams;
        ERC20 assetIn;
        uint96 minUSDValueToSwap;
    }

    /*//////////////////////////////////////////////////////////////
                             GLOBAL STATE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Curve registry exchange contract.
     * @dev Mainnet Address 0x81C46fECa27B31F3ADC2b91eE4be9717d1cd3DD7
     */
    ICurveSwaps public curveRegistryExchange;

    /**
     * @notice Convex Pool Id.
     */
    uint256 public pid;

    /**
     * @notice Covnex Rewarder contract.
     */
    IBaseRewardPool public rewarder;

    /**
     * @notice Convex Booster contract.
     */
    IBooster private booster;

    /**
     * @notice Convex reward assets
     */
    ERC20[] public rewardTokens;

    /**
     * @notice Mainnet token contracts important for this vault.
     */
    ERC20 private constant WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private constant CVX = ERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    ERC20 private constant CRV = ERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);

    /**
     * @notice Deposit parameters used by the vault to deposit into desired Curve Pool.
     */
    CurveDepositParams private depositParams;

    /**
     * @notice Stores swapping information to go from an arbitrary reward token to ETH.
     */
    mapping(ERC20 => CurveSwapParams) public arbitraryToEth;

    /**
     * @notice Stores swapping information to go from ETH to target token to supply liquidity on Curve.
     */
    CurveSwapParams public ethToTarget;

    // Owner needs to be able to set swap paths, deposit data, fee, fee accumulator
    /**
     * @notice Value out from harvest swaps must be greater than value in * 1 - (harvestSlippage + upkeepFee);
     */
    uint64 public harvestSlippage = 0.01e18;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event EthToTargetSwapParamsChanged(CurveSwapParams params);
    event ArbitraryToEthSwapParamsChanged(address asset, CurveSwapParams params);
    event HarvestSlippageChanged(uint64 slippage);
    event CurveDepositParamsChanged(CurveDepositParams params);
    event Harvest(uint256 yield);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error ConvexPositionVault__UnsupportedCurveDeposit();
    error ConvexPositionVault__BadSlippage();
    error ConvexPositionVault__WatchdogNotSet();
    error ConvexPositionVault__LengthMismatch();

    /*//////////////////////////////////////////////////////////////
                              SETUP LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Vaults are designed to be deployed using Minimal Proxy Contracts, but they can be deployed normally,
     *         but `initialize` must ALWAYS be called either way.
     */
    constructor(
        ERC20 _asset,
        address _owner,
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) BasePositionVault(_asset, _name, _symbol, _decimals, _owner) {}

    /**
     * @notice Initialize function to fully setup this vault.
     */
    function initialize(
        ERC20 _asset,
        address _owner,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        BasePositionVault.PositionVaultMetaData calldata _metaData,
        bytes memory _initializeData
    ) public override initializer {
        super.initialize(_asset, _owner, _name, _symbol, _decimals, _metaData, _initializeData);
        (
            uint256 _pid,
            IBaseRewardPool _rewarder,
            IBooster _booster,
            ERC20[] memory _rewardTokens,
            CurveDepositParams memory _depositParams,
            ICurveSwaps _curveSwaps,
            CurveSwapParams[] memory swapsToETH,
            ERC20[] memory assetsToETH,
            CurveSwapParams memory swapsFromETH
        ) = abi.decode(
                _initializeData,
                (
                    uint256,
                    IBaseRewardPool,
                    IBooster,
                    ERC20[],
                    CurveDepositParams,
                    ICurveSwaps,
                    CurveSwapParams[],
                    ERC20[],
                    CurveSwapParams
                )
            );
        pid = _pid;
        rewarder = _rewarder;
        booster = _booster;
        rewardTokens = _rewardTokens;
        depositParams = _depositParams;
        curveRegistryExchange = _curveSwaps;

        if (swapsToETH.length != assetsToETH.length) revert ConvexPositionVault__LengthMismatch();
        for (uint256 i; i < swapsToETH.length; ++i) {
            arbitraryToEth[assetsToETH[i]] = swapsToETH[i];
        }
        ethToTarget = swapsFromETH;
    }

    /*//////////////////////////////////////////////////////////////
                              OWNER LOGIC
    //////////////////////////////////////////////////////////////*/

    function updateEthTotargetSwapPath(CurveSwapParams memory params) external onlyOwner {
        ethToTarget = params;
        emit EthToTargetSwapParamsChanged(params);
    }

    function updateArbitraryToEthSwapPath(ERC20 assetIn, CurveSwapParams memory params) external onlyOwner {
        arbitraryToEth[assetIn] = params;
        emit ArbitraryToEthSwapParamsChanged(address(assetIn), params);
    }

    function updateHarvestSlippage(uint64 _slippage) external onlyOwner {
        harvestSlippage = _slippage;
        emit HarvestSlippageChanged(_slippage);
    }

    function updateCurveDepositParams(CurveDepositParams memory params) external onlyOwner {
        depositParams = params;
        emit CurveDepositParamsChanged(params);
    }

    function setRewardTokens(ERC20[] memory _rewardTokens) external onlyOwner {
        rewardTokens = _rewardTokens;
    }

    /*//////////////////////////////////////////////////////////////
                          EXTERNAL POSITION LOGIC
    //////////////////////////////////////////////////////////////*/

    function harvest(bytes memory) public override whenNotShutdown nonReentrant returns (uint256 yield) {
        uint256 pending = _calculatePendingRewards();
        if (pending > 0) {
            // We need to claim vested rewards.
            _vestRewards(_totalAssets + pending);
        }

        // Can only harvest once previous reward period is done.
        if (positionVaultAccounting._lastVestClaim >= positionVaultAccounting._vestingPeriodEnd) {
            // Harvest convex position.
            rewarder.getReward(address(this), true);

            // Claim extra rewards
            uint256 extraRewardsLength = rewarder.extraRewardsLength();
            for (uint256 i = 0; i < extraRewardsLength; i++) {
                IRewards extraReward = IRewards(rewarder.extraRewards(i));
                extraReward.getReward();
            }

            uint256 valueIn;
            uint256 ethOut;
            address[4] memory pools;
            uint256 rewardTokenCount = rewardTokens.length;
            for (uint256 i = 0; i < rewardTokenCount; i++) {
                ERC20 rewardToken = rewardTokens[i];
                uint256 rewardBalance = rewardToken.balanceOf(address(this));
                // Take platform fee
                uint256 protocolFee = rewardBalance.mulDivDown(positionVaultMetaData.platformFee, 1e18);
                rewardBalance -= protocolFee;
                rewardToken.safeTransfer(positionVaultMetaData.feeAccumulator, protocolFee);
                // Get the reward token value in USD.
                uint256 valueInUSD = rewardBalance.mulDivDown(
                    positionVaultMetaData.priceRouter.getPriceInUSD(rewardToken),
                    10 ** rewardToken.decimals()
                );
                CurveSwapParams memory swapParams = arbitraryToEth[rewardToken];
                // Check if value is enough to warrant a swap. And that we have the swap params set up for it.
                if (valueInUSD >= swapParams.minUSDValueToSwap && address(swapParams.assetIn) != address(0)) {
                    valueIn += valueInUSD;
                    // Perform Swap into ETH.
                    rewardToken.safeApprove(address(curveRegistryExchange), rewardBalance);
                    ethOut += curveRegistryExchange.exchange_multiple(
                        swapParams.route,
                        swapParams.swapParams,
                        rewardBalance,
                        0,
                        pools,
                        address(this)
                    );
                }
            }

            // Check if we even have any ETH from swaps, if not return 0;
            if (ethOut == 0) return 0;
            // Take upkeep fee.
            uint256 feeForUpkeep = ethOut.mulDivDown(positionVaultMetaData.upkeepFee, 1e18);
            // If watchdog is set, transfer WETH to it otherwise, leave it here.
            if (positionVaultMetaData.positionWatchdog == address(0)) revert ConvexPositionVault__WatchdogNotSet();
            // Transfer WETH fee to watchdog
            WETH.safeTransfer(positionVaultMetaData.positionWatchdog, feeForUpkeep);
            ethOut -= feeForUpkeep;

            uint256 assetsOut;
            // Convert assets into targetAsset.
            if (depositParams.targetAsset != WETH) {
                CurveSwapParams memory swapParams = ethToTarget;
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
            uint256 valueOut = assetsOut.mulDivDown(
                positionVaultMetaData.priceRouter.getPriceInUSD(depositParams.targetAsset),
                10 ** depositParams.targetAsset.decimals()
            );

            // Compare value in vs value out.
            if (valueOut < valueIn.mulDivDown(1e18 - (positionVaultMetaData.upkeepFee + harvestSlippage), 1e18))
                revert ConvexPositionVault__BadSlippage();

            // Deposit assets to Curve.
            _addLiquidityToCurve(assetsOut);

            // Deposit Assets to Convex.
            yield = asset.balanceOf(address(this));
            _deposit(yield);

            // Update Vesting info.
            positionVaultAccounting._rewardRate = uint128(yield.mulDivDown(REWARD_SCALER, REWARD_PERIOD));
            positionVaultAccounting._vestingPeriodEnd = uint64(block.timestamp) + REWARD_PERIOD;
            positionVaultAccounting._lastVestClaim = uint64(block.timestamp);
            emit Harvest(yield);
        } // else yield is zero.
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL POSITION LOGIC
    //////////////////////////////////////////////////////////////*/

    function _withdraw(uint256 assets) internal override {
        IBaseRewardPool rewardPool = IBaseRewardPool(rewarder);
        rewardPool.withdrawAndUnwrap(assets, false);
    }

    function _deposit(uint256 assets) internal override {
        asset.safeApprove(address(booster), assets);
        booster.deposit(pid, assets, true);
    }

    function _getRealPositionBalance() internal view override returns (uint256) {
        IBaseRewardPool rewardPool = IBaseRewardPool(rewarder);
        return rewardPool.balanceOf(address(this));
    }

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
        } else revert ConvexPositionVault__UnsupportedCurveDeposit();
    }
}
