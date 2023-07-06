// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import { BasePositionVault, ERC4626, SafeTransferLib, ERC20, Math, PriceRouter } from "./BasePositionVault.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

// External interfaces
import { IBooster } from "contracts/interfaces/external/convex/IBooster.sol";
import { IBaseRewardPool } from "contracts/interfaces/external/convex/IBaseRewardPool.sol";
import { IRewards } from "contracts/interfaces/external/convex/IRewards.sol";
import { ICurveFi } from "contracts/interfaces/external/curve/ICurveFi.sol";
import { ICurveSwaps } from "contracts/interfaces/external/curve/ICurveSwaps.sol";

// Chainlink interfaces
import { KeeperCompatibleInterface } from "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";
import { AggregatorV2V3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";
import { IChainlinkAggregator } from "contracts/interfaces/external/chainlink/IChainlinkAggregator.sol";

contract ConvexPositionVault is BasePositionVault {
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
    ERC20 private constant WETH =
        ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private constant CVX =
        ERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    ERC20 private constant CRV =
        ERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);

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
    event ArbitraryToEthSwapParamsChanged(
        address asset,
        CurveSwapParams params
    );
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
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        ICentralRegistry _centralRegistry
    ) BasePositionVault(_asset, _name, _symbol, _decimals, _centralRegistry) {}

    /**
     * @notice Initialize function to fully setup this vault.
     */
    function initialize(
        ERC20 _asset,
        ICentralRegistry _centralRegistry,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        BasePositionVault.PositionVaultMetaData calldata _metaData,
        bytes memory _initializeData
    ) public override initializer {
        super.initialize(
            _asset,
            _centralRegistry,
            _name,
            _symbol,
            _decimals,
            _metaData,
            _initializeData
        );
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

        uint256 numSwapsToETH = swapsToETH.length;

        if (numSwapsToETH != assetsToETH.length)
            revert ConvexPositionVault__LengthMismatch();
        for (uint256 i; i < numSwapsToETH; ++i) {
            arbitraryToEth[assetsToETH[i]] = swapsToETH[i];
        }
        ethToTarget = swapsFromETH;
    }

    /*//////////////////////////////////////////////////////////////
                              OWNER LOGIC
    //////////////////////////////////////////////////////////////*/

    function updateEthTotargetSwapPath(
        CurveSwapParams calldata params
    ) external onlyDaoManager {
        ethToTarget = params;
        emit EthToTargetSwapParamsChanged(params);
    }

    function updateArbitraryToEthSwapPath(
        ERC20 assetIn,
        CurveSwapParams calldata params
    ) external onlyDaoManager {
        arbitraryToEth[assetIn] = params;
        emit ArbitraryToEthSwapParamsChanged(address(assetIn), params);
    }

    function updateHarvestSlippage(uint64 _slippage) external onlyDaoManager {
        harvestSlippage = _slippage;
        emit HarvestSlippageChanged(_slippage);
    }

    function updateCurveDepositParams(
        CurveDepositParams calldata params
    ) external onlyDaoManager {
        depositParams = params;
        emit CurveDepositParamsChanged(params);
    }

    function setRewardTokens(
        ERC20[] calldata _rewardTokens
    ) external onlyDaoManager {
        rewardTokens = _rewardTokens;
    }

    /*//////////////////////////////////////////////////////////////
                          EXTERNAL POSITION LOGIC
    //////////////////////////////////////////////////////////////*/

    function harvest(
        bytes memory
    ) public override whenNotShutdown nonReentrant returns (uint256 yield) {
        uint256 pending = _calculatePendingRewards();
        if (pending > 0) {
            // We need to claim vested rewards.
            _vestRewards(_totalAssets + pending);
        }

        // Can only harvest once previous reward period is done.
        if (
            positionVaultAccounting._lastVestClaim >=
            positionVaultAccounting._vestingPeriodEnd
        ) {
            // Harvest convex position.
            rewarder.getReward(address(this), true);

            // Claim extra rewards
            uint256 extraRewardsLength = rewarder.extraRewardsLength();
            for (uint256 i = 0; i < extraRewardsLength; ++i) {
                IRewards extraReward = IRewards(rewarder.extraRewards(i));
                extraReward.getReward();
            }

            uint256 valueIn;
            uint256 ethOut;
            uint256 rewardTokenCount = rewardTokens.length;
            address[4] memory pools;

            {
                ERC20 rewardToken;
                uint256 rewardBalance;
                uint256 protocolFee;
                uint256 rewardPrice;
                uint256 valueInUSD;

                for (uint256 i = 0; i < rewardTokenCount; ++i) {
                    rewardToken = rewardTokens[i];
                    rewardBalance = rewardToken.balanceOf(address(this));
                    // Take platform fee
                    protocolFee = rewardBalance.mulDivDown(
                        positionVaultMetaData.platformFee,
                        1e18
                    );
                    rewardBalance -= protocolFee;
                    SafeTransferLib.safeTransfer(
                        address(rewardToken),
                        positionVaultMetaData.feeAccumulator,
                        protocolFee
                    );

                    (rewardPrice, ) = positionVaultMetaData
                        .priceRouter
                        .getPrice(address(rewardToken), true, true);

                    // Get the reward token value in USD.
                    valueInUSD = rewardBalance.mulDivDown(
                        rewardPrice,
                        10 ** rewardToken.decimals()
                    );
                    CurveSwapParams memory swapParams = arbitraryToEth[
                        rewardToken
                    ];
                    // Check if value is enough to warrant a swap. And that we have the swap params set up for it.
                    if (
                        valueInUSD >= swapParams.minUSDValueToSwap &&
                        address(swapParams.assetIn) != address(0)
                    ) {
                        valueIn += valueInUSD;
                        // Perform Swap into ETH.
                        SafeTransferLib.safeApprove(
                            address(rewardToken),
                            address(curveRegistryExchange),
                            rewardBalance
                        );
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
            }

            // Check if we even have any ETH from swaps, if not return 0;
            if (ethOut == 0) return 0;
            // Take upkeep fee.
            uint256 feeForUpkeep = ethOut.mulDivDown(
                positionVaultMetaData.upkeepFee,
                1e18
            );
            // If watchdog is set, transfer WETH to it otherwise, leave it here.
            if (positionVaultMetaData.positionWatchdog == address(0))
                revert ConvexPositionVault__WatchdogNotSet();
            // Transfer WETH fee to watchdog
            SafeTransferLib.safeTransfer(
                address(WETH),
                positionVaultMetaData.positionWatchdog,
                feeForUpkeep
            );
            ethOut -= feeForUpkeep;

            uint256 assetsOut;
            // Convert assets into targetAsset.
            if (depositParams.targetAsset != WETH) {
                CurveSwapParams memory swapParams = ethToTarget;
                SafeTransferLib.safeApprove(
                    address(WETH),
                    address(curveRegistryExchange),
                    ethOut
                );
                assetsOut = curveRegistryExchange.exchange_multiple(
                    swapParams.route,
                    swapParams.swapParams,
                    ethOut,
                    0,
                    pools,
                    address(this)
                );
            } else assetsOut = ethOut;

            (uint256 assetPrice, ) = positionVaultMetaData
                .priceRouter
                .getPrice(address(depositParams.targetAsset), true, true);

            uint256 valueOut = assetsOut.mulDivDown(
                assetPrice,
                10 ** depositParams.targetAsset.decimals()
            );

            // Compare value in vs value out.
            if (
                valueOut <
                valueIn.mulDivDown(
                    1e18 - (positionVaultMetaData.upkeepFee + harvestSlippage),
                    1e18
                )
            ) revert ConvexPositionVault__BadSlippage();

            // Deposit assets to Curve.
            _addLiquidityToCurve(assetsOut);

            // Deposit Assets to Convex.
            yield = ERC20(asset()).balanceOf(address(this));
            _deposit(yield);

            // Update Vesting info.
            positionVaultAccounting._rewardRate = uint128(
                yield.mulDivDown(REWARD_SCALER, REWARD_PERIOD)
            );
            positionVaultAccounting._vestingPeriodEnd =
                uint64(block.timestamp) +
                REWARD_PERIOD;
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
        SafeTransferLib.safeApprove(asset(), address(booster), assets);
        booster.deposit(pid, assets, true);
    }

    function _getRealPositionBalance()
        internal
        view
        override
        returns (uint256)
    {
        IBaseRewardPool rewardPool = IBaseRewardPool(rewarder);
        return rewardPool.balanceOf(address(this));
    }

    function _addLiquidityToCurve(uint256 amount) internal {
        SafeTransferLib.safeApprove(
            address(depositParams.targetAsset),
            depositParams.pool,
            amount
        );
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
