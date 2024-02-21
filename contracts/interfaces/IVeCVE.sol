// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { RewardsData } from "contracts/interfaces/ICVELocker.sol";
import "contracts/token/VeCVE.sol";

interface IVeCVE {

    /// @notice Locks a given amount of cve tokens on behalf of another user,
    ///         and processes any pending locker rewards.
    /// @param recipient The address to lock tokens for.
    /// @param amount The amount of tokens to lock.
    /// @param continuousLock Indicator of whether the lock should be continuous.
    /// @param rewardsData Rewards data for CVE rewards locker.
    /// @param params Parameters for rewards claim function.
    /// @param aux Auxiliary data.
    function createLockFor(
        address recipient,
        uint256 amount,
        bool continuousLock,
        RewardsData memory rewardsData,
        bytes memory params,
        uint256 aux
    ) external;

    /// @notice Increases the locked amount and extends the lock
    ///         for the specified lock index, and processes any pending
    ///         locker rewards.
    /// @param recipient The address to lock and extend tokens for.
    /// @param amount The amount to increase the lock by.
    /// @param lockIndex The index of the lock to extend.
    /// @param continuousLock Whether the lock should be continuous or not.
    /// @param rewardsData Rewards data for CVE rewards locker.
    /// @param params Parameters for rewards claim function.
    /// @param aux Auxiliary data.
    function increaseAmountAndExtendLockFor(
        address recipient,
        uint256 amount,
        uint256 lockIndex,
        bool continuousLock,
        RewardsData memory rewardsData,
        bytes memory params,
        uint256 aux
    ) external;

    /// @notice Used for frontend, needed due to array of structs.
    /// @param user The user to query veCVE locks for.
    /// @return Unwrapped user lock information.
    function queryUserLocks(
        address user
    ) external view returns (uint256[] memory, uint256[] memory);

    /// @notice Returns the chain's current token points for
    function chainPoints() external view returns (uint256);

    /// @notice Returns the chain's token unlocks for an epoch.
    /// @param epoch The epoch to query token unlocks for.
    function chainUnlocksByEpoch(
        uint256 epoch
    ) external view returns (uint256);

    /// @notice Token Points on this chain.
    /// @param user User to query points for.
    function userPoints(address user) external view returns (uint256);

    /// @notice Returns a user's token unlocks for an epoch.
    /// @param user User to query token unlocks for.
    /// @param epoch The epoch to query token unlocks for.
    function userUnlocksByEpoch(
        address user,
        uint256 epoch
    ) external view returns (uint256);

    /// @notice Updates user points by reducing the amount that gets unlocked
    ///         in a specific epoch.
    /// @param user The address of the user whose points are to be updated.
    /// @param epoch The epoch from which the unlock amount will be reduced.
    /// @dev This function is only called when
    ///      userUnlocksByEpoch[user][epoch] > 0
    ///      so we do not need to check here.
    function updateUserPoints(address user, uint256 epoch) external;

    /// @notice Returns the timestamp of when the next epoch begins.
    /// @return The calculated next epoch start timestamp.
    function nextEpochStartTime() external view returns (uint256);
}
