// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CTokenCompounding, SafeTransferLib, IERC20, Math, ICentralRegistry } from "contracts/market/collateral/CTokenCompounding.sol";

import { WAD } from "contracts/libraries/Constants.sol";

import { IStakedGMX } from "contracts/interfaces/external/gmx/IStakedGMX.sol";
import { IRewardRouter } from "contracts/interfaces/external/gmx/IRewardRouter.sol";

contract StakedGMXCToken is CTokenCompounding {
    using Math for uint256;

    /// CONSTANTS ///

    IERC20 public immutable rewardToken;

    /// STORAGE ///

    IRewardRouter public rewardRouter;

    /// EVENTS ///

    event Harvest(uint256 yield);

    /// ERRORS ///

    error StakedGMXCToken__ChainIsNotSupported();
    error StakedGMXCToken__InvalidRewardRouter();

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        IERC20 asset_,
        address marketManager_,
        address rewardRouter_
    ) CTokenCompounding(centralRegistry_, asset_, marketManager_) {
        if (block.chainid != 42161) {
            revert StakedGMXCToken__ChainIsNotSupported();
        }

        _setRewardRouter(rewardRouter_);
        rewardToken = IERC20(IStakedGMX(asset()).rewardToken());
    }

    /// EXTERNAL FUNCTIONS ///

    receive() external payable {}

    // REWARD AND HARVESTING LOGIC

    /// @notice Harvests and compounds outstanding vault rewards and
    ///         vests pending rewards.
    /// @dev Only callable by Gelato Network bot.
    function harvest(
        bytes calldata
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
                uint256 protocolFee = rewardAmount.mulDivDown(
                    centralRegistry.protocolHarvestFee(),
                    1e18
                );
                rewardAmount -= protocolFee;
                SafeTransferLib.safeTransfer(
                    address(rewardToken),
                    centralRegistry.feeAccumulator(),
                    protocolFee
                );
            }

            uint256 balance = IERC20(asset()).balanceOf(address(this));

            // Deposit claimed reward to StakedGMX.
            SafeTransferLib.safeApprove(
                address(rewardToken),
                address(rewardRouter),
                rewardAmount
            );
            rewardRouter.stakeEsGmx(rewardAmount);

            yield = IERC20(asset()).balanceOf(address(this)) - balance;

            // Update vesting info.
            // Cache vest period so we do not need to load it twice.
            uint256 _vestPeriod = vestPeriod;
            _vaultData = _packVaultData(
                yield.mulDivDown(WAD, _vestPeriod),
                block.timestamp + _vestPeriod
            );

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
        if (!IStakedGMX(asset()).isHandler(newRouter)) {
            revert StakedGMXCToken__InvalidRewardRouter();
        }

        rewardRouter = IRewardRouter(newRouter);
    }

    // INTERNAL POSITION LOGIC

    /// @notice Gets the balance of assets inside StakedGMX.
    /// @return The current balance of assets.
    function _getRealPositionBalance()
        internal
        view
        override
        returns (uint256)
    {
        return IERC20(asset()).balanceOf(address(this));
    }

    /// @notice Claim reward from StakedGMX.
    function _claimReward() internal returns (uint256 rewardAmount) {
        uint256 balance = rewardToken.balanceOf(address(this));

        // claim reward from StakedGMX.
        rewardRouter.claimEsGmx();

        return rewardToken.balanceOf(address(this)) - balance;
    }
}
