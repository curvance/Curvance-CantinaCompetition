// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CTokenCompounding, FixedPointMathLib, SafeTransferLib, IERC20, ICentralRegistry } from "contracts/market/collateral/CTokenCompounding.sol";

import { VelodromeLib } from "contracts/libraries/VelodromeLib.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";

import { IVeloGauge } from "contracts/interfaces/external/velodrome/IVeloGauge.sol";
import { IVeloRouter } from "contracts/interfaces/external/velodrome/IVeloRouter.sol";
import { IVeloPair } from "contracts/interfaces/external/velodrome/IVeloPair.sol";
import { IVeloPairFactory } from "contracts/interfaces/external/velodrome/IVeloPairFactory.sol";
import { IVeloPool } from "contracts/interfaces/external/velodrome/IVeloPool.sol";

contract VelodromeStableCToken is CTokenCompounding {
    /// TYPES ///

    /// @param gauge Address of Velodrome Gauge.
    /// @param pairFactory Address of Velodrome Pair Factory.
    /// @param router Address of Velodrome Router.
    /// @param token0 Address of first underlying token.
    /// @param token1 Address of second underlying token.
    /// @param decimalsA Token decimals of Token0.
    /// @param decimalsB Token decimals of Token1.
    struct StrategyData {
        IVeloGauge gauge;
        IVeloPairFactory pairFactory;
        IVeloRouter router;
        address token0;
        address token1;
        uint256 decimalsA;
        uint256 decimalsB;
    }

    /// CONSTANTS ///

    /// @notice VELO contract address, only available on Optimism network.
    IERC20 public constant rewardToken =
        IERC20(0x9560e827aF36c94D2Ac33a39bCE1Fe78631088Db);
    /// @notice Whether VELO is an underlying token of the pair,
    ///         e.g. VELO/Liquid wrapped VELO LP token.
    bool public immutable rewardTokenIsUnderlying;

    /// STORAGE ///

    /// @notice StrategyData packed configuration data.
    StrategyData public strategyData;

    /// @notice Whether a particular token address is an underlying token
    ///         of this sAMM LP.
    /// @dev Token => Is underlying token.
    mapping(address => bool) public isUnderlyingToken;

    /// EVENTS ///

    event Harvest(uint256 yield);

    /// ERRORS ///

    error VelodromeStableCToken__ChainIsNotSupported();
    error VelodromeStableCToken__StakingTokenIsNotAsset(address stakingToken);
    error VelodromeStableCToken__AssetIsNotStable();
    error VelodromeStableCToken__SlippageError();
    error VelodromeStableCToken__InvalidSwapper(address invalidSwapper);

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        IERC20 asset_,
        address marketManager_,
        IVeloGauge gauge,
        IVeloPairFactory pairFactory,
        IVeloRouter router
    ) CTokenCompounding(centralRegistry_, asset_, marketManager_) {
        if (block.chainid != 10) {
            revert VelodromeStableCToken__ChainIsNotSupported();
        }

        // Cache assigned asset address.
        address _asset = asset();
        // Validate that we have the proper gauge linked with the proper LP
        // and pair factory.
        if (gauge.stakingToken() != _asset) {
            revert VelodromeStableCToken__StakingTokenIsNotAsset(
                gauge.stakingToken()
            );
        }

        // Validate the desired underlying lp token is an sAMM.
        if (!IVeloPool(_asset).stable()) {
            revert VelodromeStableCToken__AssetIsNotStable();
        }

        // Query underlying token data from the pool.
        strategyData.token0 = IVeloPool(_asset).token0();
        strategyData.token1 = IVeloPool(_asset).token1();
        // Make sure token0 is VELO if one of underlying tokens is VELO,
        // so that it can be used properly in harvest function.
        if (strategyData.token1 == address(rewardToken)) {
            strategyData.token1 = strategyData.token0;
            strategyData.token0 = address(rewardToken);
        }
        strategyData.decimalsA = 10 ** IERC20(strategyData.token0).decimals();
        strategyData.decimalsB = 10 ** IERC20(strategyData.token1).decimals();

        strategyData.gauge = gauge;
        strategyData.router = router;
        strategyData.pairFactory = pairFactory;

        isUnderlyingToken[strategyData.token0] = true;
        isUnderlyingToken[strategyData.token1] = true;

        rewardTokenIsUnderlying = (address(rewardToken) ==
            strategyData.token0 ||
            address(rewardToken) == strategyData.token1);
    }

    /// PUBLIC FUNCTIONS ///

    // REWARD AND HARVESTING LOGIC

    /// @notice Harvests and compounds outstanding vault rewards
    ///         and vests pending rewards.
    /// @dev Only callable by Gelato Network bot.
    ///      Emits a {Harvest} event.
    /// @param data Byte array for aggregator swap data.
    /// @return yield The amount of new assets acquired from compounding
    ///               vault yield.
    function harvest(
        bytes calldata data
    ) external override returns (uint256 yield) {
        // Checks whether the caller can compound the vault yield.
        _canCompound();

        // Vest pending rewards if there are any.
        _vestIfNeeded();

        // Can only harvest once previous reward period is done.
        if (_checkVestStatus(_vaultData)) {
            _updateVestingPeriodIfNeeded();

            // Cache strategy data.
            StrategyData memory sd = strategyData;

            // Claim pending Velodrome rewards.
            sd.gauge.getReward(address(this));

            {
                uint256 rewardAmount = rewardToken.balanceOf(address(this));
                // If there are no pending rewards, skip swapping logic.
                if (rewardAmount > 0) {
                    // Take protocol fee for veCVE lockers and auto
                    // compounding bot.
                    uint256 protocolFee = FixedPointMathLib.mulDiv(
                        rewardAmount, 
                        centralRegistry.protocolHarvestFee(),
                        1e18
                    );
                    rewardAmount -= protocolFee;
                    SafeTransferLib.safeTransfer(
                        address(rewardToken),
                        centralRegistry.feeAccumulator(),
                        protocolFee
                    );

                    // Swap from VELO to underlying tokens, if necessary.
                    if (!rewardTokenIsUnderlying) {
                        SwapperLib.Swap memory swapData = abi.decode(
                            data,
                            (SwapperLib.Swap)
                        );

                        if (!centralRegistry.isSwapper(swapData.target)) {
                            revert VelodromeStableCToken__InvalidSwapper(
                                swapData.target
                            );
                        }

                        SwapperLib.swap(centralRegistry, swapData);
                    }
                }
            }

            uint256 totalAmountA = IERC20(sd.token0).balanceOf(address(this));

            // Make sure swap was routed into token0, or that token0 is VELO.
            if (totalAmountA == 0) {
                revert VelodromeStableCToken__SlippageError();
            }

            // Cache asset to minimize storage reads.
            address _asset = asset();
            // Pull reserve data so we can swap half of token0 into token1
            // optimally.
            (uint256 r0, uint256 r1, ) = IVeloPair(_asset).getReserves();
            (uint256 reserveA, uint256 reserveB) = sd.token0 ==
                IVeloPair(_asset).token0()
                ? (r0, r1)
                : (r1, r0);
            // Feed library pair factory, lpToken, and stable = true, 
            // plus calculated data.
            uint256 swapAmount = VelodromeLib._optimalDeposit(
                address(sd.pairFactory),
                _asset,
                totalAmountA,
                reserveA,
                reserveB,
                sd.decimalsA,
                sd.decimalsB,
                true
            );
            // Feed calculated data, and stable = true.
            VelodromeLib._swapExactTokensForTokens(
                address(sd.router),
                _asset,
                sd.token0,
                sd.token1,
                swapAmount,
                true
            );
            totalAmountA -= swapAmount;

            // Add liquidity to Velodrome lp with stable params.
            yield = VelodromeLib._addLiquidity(
                address(sd.router),
                sd.token0,
                sd.token1,
                true,
                totalAmountA,
                IERC20(sd.token1).balanceOf(address(this)), // totalAmountB
                VelodromeLib.VELODROME_ADD_LIQUIDITY_SLIPPAGE
            );

            // Deposit new assets into Velodrome gauge to continue
            // yield farming.
            _afterDeposit(yield, 0);

            // Update vesting info, query `vestPeriod` here to cache it.
            _setNewVaultData(yield, vestPeriod);

            emit Harvest(yield);
        }
    }

    /// INTERNAL FUNCTIONS ///

    // INTERNAL POSITION LOGIC

    /// @notice Deposits specified amount of assets into velodrome gauge pool.
    /// @param assets The amount of assets to deposit.
    function _afterDeposit(uint256 assets, uint256) internal override {
        IVeloGauge gauge = strategyData.gauge;
        SafeTransferLib.safeApprove(asset(), address(gauge), assets);
        gauge.deposit(assets);
    }

    /// @notice Withdraws specified amount of assets from velodrome gauge pool.
    /// @param assets The amount of assets to withdraw.
    function _beforeWithdraw(uint256 assets, uint256) internal override {
        strategyData.gauge.withdraw(assets);
    }
}
