// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CTokenCompounding, SafeTransferLib, IERC20, FixedPointMathLib, ICentralRegistry } from "contracts/market/collateral/CTokenCompounding.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { IStakedGMX } from "contracts/interfaces/external/gmx/IStakedGMX.sol";
import { IRewardRouter } from "contracts/interfaces/external/gmx/IRewardRouter.sol";

contract StakedGMXCToken is CTokenCompounding {
    /// CONSTANTS ///

    /// @notice The address of WETH on this chain.
    IERC20 public immutable WETH;

    /// STORAGE ///

    /// @notice The address of the GMX reward router that distributes WETH
    ///         yield to staked GMX positions.
    IRewardRouter public rewardRouter;

    /// EVENTS ///

    event Harvest(uint256 yield);

    /// ERRORS ///

    error StakedGMXCToken__SlippageError();
    error StakedGMXCToken__InvalidRewardRouter();
    error StakedGMXCToken__InvalidWETH();
    error StakedGMXCToken__InvalidSwapper(address invalidSwapper);
    error StakedGMXCToken__ChainIsNotSupported();

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

            // Claim pending Staked GMX rewards.
            rewardRouter.handleRewards(
                true,
                true,
                true,
                true,
                true,
                true,
                false
            );
            uint256 rewardAmount = WETH.balanceOf(address(this));

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
                    address(WETH),
                    centralRegistry.feeAccumulator(),
                    protocolFee
                );

                SwapperLib.Swap memory swapData = abi.decode(
                    data,
                    (SwapperLib.Swap)
                );

                if (!centralRegistry.isSwapper(swapData.target)) {
                    revert StakedGMXCToken__InvalidSwapper(swapData.target);
                }

                yield = SwapperLib.swap(centralRegistry, swapData);
            }

            // Make sure swap was routed into GMX.
            if (yield == 0) {
                revert StakedGMXCToken__SlippageError();
            }

            // Deposit new assets into Staked GMX contract to continue
            // yield farming.
            _afterDeposit(yield, 0);

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

    /// @notice Deposits specified amount of assets into Staked GMX contract.
    /// @param assets The amount of assets to deposit.
    function _afterDeposit(uint256 assets, uint256) internal override {
        SafeTransferLib.safeApprove(
            asset(),
            rewardRouter.stakedGmxTracker(),
            assets
        );
        rewardRouter.stakeGmx(assets);
    }

    /// @notice Withdraws specified amount of assets from Staked GMX contract.
    /// @param assets The amount of assets to withdraw.
    function _beforeWithdraw(uint256 assets, uint256) internal override {
        rewardRouter.unstakeGmx(assets);
    }
}
