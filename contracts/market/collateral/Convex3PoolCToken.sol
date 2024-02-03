// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CTokenCompounding, FixedPointMathLib, SafeTransferLib, IERC20, ICentralRegistry } from "contracts/market/collateral/CTokenCompounding.sol";

import { CommonLib } from "contracts/libraries/CommonLib.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";

import { IBooster } from "contracts/interfaces/external/convex/IBooster.sol";
import { IBaseRewardPool } from "contracts/interfaces/external/convex/IBaseRewardPool.sol";
import { IRewards } from "contracts/interfaces/external/convex/IRewards.sol";
import { ICurveFi } from "contracts/interfaces/external/curve/ICurveFi.sol";

contract Convex3PoolCToken is CTokenCompounding {
    /// TYPES ///

    /// @param curvePool Address for Curve Pool.
    /// @param pid Convex pool id value.
    /// @param rewarder Address for Convex Rewarder contract.
    /// @param booster Address for Convex Booster contract.
    /// @param rewardTokens Array of Convex reward tokens.
    /// @param underlyingTokens Curve LP underlying tokens.
    struct StrategyData {
        ICurveFi curvePool;
        uint256 pid;
        IBaseRewardPool rewarder;
        IBooster booster;
        address[] rewardTokens;
        address[] underlyingTokens;
    }

    /// CONSTANTS ///

    /// @dev This address is for Ethereum mainnet so make sure to update
    ///      it if Curve/Convex is being supported on another chain
    address private constant _CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;

    /// STORAGE ///

    //// @notice StrategyData packed configuration data.
    StrategyData public strategyData;

    /// @notice Whether a particular token address is an underlying token
    ///         of this Curve 3Pool lp.
    /// @dev Token => Is underlying token.
    mapping(address => bool) public isUnderlyingToken;

    /// EVENTS ///

    event Harvest(uint256 yield);

    /// ERRORS ///

    error Convex3PoolCToken__UnsafePool();
    error Convex3PoolCToken__InvalidVaultConfig();
    error Convex3PoolCToken__InvalidCoinLength();
    error Convex3PoolCToken__InvalidSwapper(
        uint256 index,
        address invalidSwapper
    );
    error Convex3PoolCToken__NoYield();

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        IERC20 asset_,
        address marketManager_,
        uint256 pid_,
        address rewarder_,
        address booster_
    ) CTokenCompounding(centralRegistry_, asset_, marketManager_) {
        // We only support Curves new ng pools with read only
        // reentry protection. This may be adjusted in the future.
        if (pid_ <= 176) {
            revert Convex3PoolCToken__UnsafePool();
        }

        strategyData.pid = pid_;
        strategyData.booster = IBooster(booster_);

        // Query actual Convex pool configuration data.
        (address pidToken, , , address crvRewards, , bool shutdown) = IBooster(
            booster_
        ).poolInfo(strategyData.pid);

        // Validate that the pool is still active and that the lp token
        // and rewarder in Convex matches what we are configuring for.
        if (
            pidToken != address(asset_) || shutdown || crvRewards != rewarder_
        ) {
            revert Convex3PoolCToken__InvalidVaultConfig();
        }

        strategyData.curvePool = ICurveFi(pidToken);

        uint256 coinsLength;
        address token;

        // Figure out how many tokens are in the Curve pool.
        while (true) {
            try ICurveFi(pidToken).coins(coinsLength) {
                ++coinsLength;
            } catch {
                break;
            }
        }

        // Validate that the liquidity pool is actually a 3Pool.
        if (coinsLength != 3) {
            revert Convex3PoolCToken__InvalidCoinLength();
        }

        strategyData.rewarder = IBaseRewardPool(rewarder_);

        // Add CRV as a reward token, then let Convex tell you what rewards
        // the vault will receive.
        strategyData.rewardTokens.push() = _CRV;
        uint256 extraRewardsLength = IBaseRewardPool(rewarder_)
            .extraRewardsLength();
        for (uint256 i; i < extraRewardsLength; ++i) {
            strategyData.rewardTokens.push() = IRewards(
                IBaseRewardPool(rewarder_).extraRewards(i)
            ).rewardToken();
        }

        // Let Curve lp tell you what its underlying tokens are.
        strategyData.underlyingTokens = new address[](coinsLength);
        for (uint256 i; i < coinsLength; ) {
            token = ICurveFi(pidToken).coins(i);
            strategyData.underlyingTokens[i] = token;
            isUnderlyingToken[token] = true;

            unchecked {
                ++i;
            }
        }
    }

    /// EXTERNAL FUNCTIONS ///

    // PERMISSIONED FUNCTIONS

    /// @notice Requeries reward tokens directly from Convex smart contracts.
    /// @dev This can be permissionless since this data is 1:1 with dependent
    ///      contracts and takes no parameters.
    function reQueryRewardTokens() external {
        delete strategyData.rewardTokens;

        // Add CRV as a reward token, then let Convex tell you what rewards
        // the vault will receive.
        strategyData.rewardTokens.push() = _CRV;
        IBaseRewardPool rewarder = strategyData.rewarder;

        uint256 extraRewardsLength = rewarder.extraRewardsLength();
        for (uint256 i; i < extraRewardsLength; ++i) {
            strategyData.rewardTokens.push() = IRewards(
                rewarder.extraRewards(i)
            ).rewardToken();
        }
    }

    /// @notice Returns this strategies reward tokens.
    function rewardTokens() external view returns (address[] memory) {
        return strategyData.rewardTokens;
    }

    /// @notice Returns this strategies base assets underlying tokens.
    function underlyingTokens() external view returns (address[] memory) {
        return strategyData.underlyingTokens;
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

            // Claim pending Convex rewards.
            sd.rewarder.getReward(address(this), true);

            (SwapperLib.Swap[] memory swapDataArray, uint256 minLPAmount) = abi
                .decode(data, (SwapperLib.Swap[], uint256));

            uint256 numRewardTokens = sd.rewardTokens.length;
            address rewardToken;
            uint256 rewardAmount;
            uint256 protocolFee;

            {
                // Cache DAO Central Registry values to minimize runtime
                // gas costs.
                address feeAccumulator = centralRegistry.feeAccumulator();
                uint256 harvestFee = centralRegistry.protocolHarvestFee();

                for (uint256 i; i < numRewardTokens; ++i) {
                    rewardToken = sd.rewardTokens[i];
                    rewardAmount = IERC20(rewardToken).balanceOf(
                        address(this)
                    );

                    // If there are no pending rewards for this token,
                    // can skip to next reward token.
                    if (rewardAmount == 0) {
                        continue;
                    }

                    // Take protocol fee for veCVE lockers and auto
                    // compounding bot.
                    protocolFee = FixedPointMathLib.mulDiv(
                        rewardAmount, 
                        harvestFee, 
                        1e18
                    );
                    rewardAmount -= protocolFee;
                    SafeTransferLib.safeTransfer(
                        address(rewardToken),
                        feeAccumulator,
                        protocolFee
                    );
                }
            }

            // Prep liquidity for Curve Pool.
            {
                uint256 numSwapData = swapDataArray.length;
                for (uint256 i; i < numSwapData; ++i) {
                    if (!centralRegistry.isSwapper(swapDataArray[i].target)) {
                        revert Convex3PoolCToken__InvalidSwapper(
                            i,
                            swapDataArray[i].target
                        );
                    }
                    SwapperLib.swap(centralRegistry, swapDataArray[i]);
                }
            }

            // Deposit assets into Curve Pool.
            _addLiquidityToCurve(minLPAmount);

            // Deposit assets into Convex.
            yield = IERC20(asset()).balanceOf(address(this));
            if (yield == 0) {
                revert Convex3PoolCToken__NoYield();
            }
            _afterDeposit(yield, 0);

            // Update vesting info, query `vestPeriod` here to cache it.
            _setNewVaultData(yield, vestPeriod);

            emit Harvest(yield);
        }
    }

    /// INTERNAL FUNCTIONS ///

    // INTERNAL POSITION LOGIC

    /// @notice Deposits specified amount of assets into Convex
    ///         booster contract.
    /// @param assets The amount of assets to deposit.
    function _afterDeposit(uint256 assets, uint256) internal override {
        IBooster booster = strategyData.booster;
        SafeTransferLib.safeApprove(asset(), address(booster), assets);
        booster.deposit(strategyData.pid, assets, true);
    }

    /// @notice Withdraws specified amount of assets from Convex reward pool.
    /// @param assets The amount of assets to withdraw.
    function _beforeWithdraw(uint256 assets, uint256) internal override {
        strategyData.rewarder.withdrawAndUnwrap(assets, false);
    }

    /// @notice Adds underlying tokens to the vaults Curve 3Pool LP.
    /// @param minLPAmount Minimum LP token amount that should be received
    ///                    on adding liquidity, this acts as a slippage check.
    function _addLiquidityToCurve(uint256 minLPAmount) internal {
        address underlyingToken;
        uint256[3] memory amounts;

        bool liquidityAvailable;
        uint256 value;
        for (uint256 i; i < 3; ++i) {
            underlyingToken = strategyData.underlyingTokens[i];
            amounts[i] = CommonLib.getTokenBalance(underlyingToken);

            if (CommonLib.isETH(underlyingToken)) {
                value = amounts[i];
            }

            SwapperLib._approveTokenIfNeeded(
                underlyingToken,
                address(strategyData.curvePool),
                amounts[i]
            );

            if (amounts[i] > 0) {
                liquidityAvailable = true;
            }
        }

        if (liquidityAvailable) {
            strategyData.curvePool.add_liquidity{ value: value }(
                amounts,
                minLPAmount
            );
        }
    }
}
