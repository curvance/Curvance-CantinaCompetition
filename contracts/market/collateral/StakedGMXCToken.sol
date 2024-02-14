// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CTokenCompounding, SafeTransferLib, IERC20, FixedPointMathLib, ICentralRegistry } from "contracts/market/collateral/CTokenCompounding.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { IStakedGMX } from "contracts/interfaces/external/gmx/IStakedGMX.sol";
import { IRewardRouter } from "contracts/interfaces/external/gmx/IRewardRouter.sol";

contract StakedGMXCToken is CTokenCompounding {
    /// CONSTANTS ///

    IERC20 public immutable WETH;

    /// STORAGE ///

    IRewardRouter public rewardRouter;

    /// EVENTS ///

    event Harvest(uint256 yield);

    /// ERRORS ///

    error StakedGMXCToken__ChainIsNotSupported();
    error StakedGMXCToken__InvalidRewardRouter();
    error StakedGMXCToken__InvalidWETH();
    error StakedGMXCToken__InvalidSwapper(address invalidSwapper);

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        IERC20 asset_, // GMX
        address marketManager_,
        address rewardRouter_,
        address weth_
    ) CTokenCompounding(centralRegistry_, asset_, marketManager_) {
        if (block.chainid != 42161) {
            revert StakedGMXCToken__ChainIsNotSupported();
        }
        if (weth_ == address(0)) {
            revert StakedGMXCToken__InvalidWETH();
        }

        _setRewardRouter(rewardRouter_);

        WETH = IERC20(weth_);
    }

    /// EXTERNAL FUNCTIONS ///

    receive() external payable {}

    // REWARD AND HARVESTING LOGIC

    /// @notice Harvests and compounds outstanding vault rewards and
    ///         vests pending rewards.
    /// @dev Only callable by Gelato Network bot.
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

            // Claim StakedGMX rewards.
            uint256 rewardAmount = _claimReward();

            if (rewardAmount > 0) {
                // Take protocol fee.
                uint256 protocolFee = FixedPointMathLib.mulDiv(
                    rewardAmount,
                    centralRegistry.protocolHarvestFee(),
                    1e18
                );
                rewardAmount -= protocolFee;
                SafeTransferLib.safeTransfer(
                    address(WETH),
                    centralRegistry.feeAccumulator(),
                    protocolFee
                );
            }

            uint256 balance = IERC20(asset()).balanceOf(address(this));

            SwapperLib.Swap memory swapData = abi.decode(
                data,
                (SwapperLib.Swap)
            );

            if (!centralRegistry.isSwapper(swapData.target)) {
                revert StakedGMXCToken__InvalidSwapper(swapData.target);
            }

            SwapperLib.swap(centralRegistry, swapData);

            yield = IERC20(asset()).balanceOf(address(this)) - balance;
            address stakedGmxTracker = rewardRouter.stakedGmxTracker();
            _totalAssets = IStakedGMX(stakedGmxTracker).stakedAmounts(
                address(this)
            );

            // Deposit swapped reward to StakedGMX.
            SafeTransferLib.safeApprove(asset(), stakedGmxTracker, yield);
            rewardRouter.stakeGmx(yield);

            // Update vesting info, query `vestPeriod` here to cache it.
            _setNewVaultData(yield, vestPeriod);

            emit Harvest(yield);
        }
    }

    /// @notice Set Reward Router address.
    function setRewardRouter(address newRouter) external {
        _checkDaoPermissions();

        _setRewardRouter(newRouter);
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Set Reward Router address.
    function _setRewardRouter(address newRouter) internal {
        if (newRouter == address(0)) {
            revert StakedGMXCToken__InvalidRewardRouter();
        }

        rewardRouter = IRewardRouter(newRouter);
    }

    // INTERNAL POSITION LOGIC

    /// @notice Deposits specified amount of assets into velodrome gauge pool
    /// @param assets The amount of assets to deposit
    function _afterDeposit(uint256 assets, uint256) internal override {
        SafeTransferLib.safeApprove(
            asset(),
            rewardRouter.stakedGmxTracker(),
            assets
        );
        rewardRouter.stakeGmx(assets);
    }

    /// @notice Withdraws specified amount of assets from velodrome gauge pool
    /// @param assets The amount of assets to withdraw
    function _beforeWithdraw(uint256 assets, uint256) internal override {
        rewardRouter.unstakeGmx(assets);
    }

    /// @notice Claim reward from StakedGMX.
    function _claimReward() internal returns (uint256 rewardAmount) {
        uint256 balance = WETH.balanceOf(address(this));

        // claim reward from StakedGMX.
        rewardRouter.handleRewards(true, true, true, true, true, true, false);

        return WETH.balanceOf(address(this)) - balance;
    }
}
