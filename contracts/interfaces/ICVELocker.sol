// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @notice Rewards data for CVE rewards locker.
/// @param asCVE Whether rewards to be routed into CVE or not.
/// @param shouldLock Indicator of whether rewards should be locked,
///                   if applicable.
/// @param isFreshLock Indicator of whether it's a fresh lock, if applicable.
/// @param isFreshLockContinuous Indicator of whether the fresh lock
///                              should be continuous.
struct RewardsData {
    bool asCVE;
    bool shouldLock;
    bool isFreshLock;
    bool isFreshLockContinuous;
}

interface ICVELocker {
    /// @notice Returns the reward token for the CVE locker.
    function rewardToken() external view returns (address);

    /// @notice Called by the fee accumulator to record rewards allocated to
    ///         an epoch.
    /// @dev Only callable on by the Fee Accumulator.
    /// @param rewardsPerCVE The rewards alloted to 1 vote escrowed CVE for
    ///                      the next reward epoch delivered.
    function recordEpochRewards(uint256 rewardsPerCVE) external;

    /// @notice Returns the current epoch for the given time.
    /// @param time The timestamp for which to calculate the epoch.
    /// @return The current epoch.
    function currentEpoch(uint256 time) external view returns (uint256);

    /// @notice The next undelivered epoch index.
    /// @dev This should be as close to currentEpoch() + 1 as possible,
    ///      but can lag behind if crosschain systems are strained.
    function nextEpochToDeliver() external view returns (uint256);

    /// @notice Updates `user`'s claim index.
    /// @dev Updates the claim index of a user.
    ///      Can only be called by the VeCVE contract.
    /// @param user The address of the user.
    /// @param index The new claim index.
    function updateUserClaimIndex(address user, uint256 index) external;

    /// @notice Resets `user`'s claim index.
    /// @dev Deletes the claim index of a user.
    ///      Can only be called by the VeCVE contract.
    /// @param user The address of the user.
    function resetUserClaimIndex(address user) external;

    /// @notice Claims rewards for multiple epochs.
    /// @param user The address of the user claiming rewards.
    /// @param epochs The number of epochs for which to claim rewards.
    /// @param rewardsData Rewards data for CVE rewards locker.
    /// @param params Swap data for token swapping rewards to
    ///               rewardsData.desiredRewardToken, if necessary.
    /// @param aux Auxiliary data for wrapped assets such as veCVE.
    function claimRewardsFor(
        address user,
        uint256 epochs,
        RewardsData memory rewardsData,
        bytes memory params,
        uint256 aux
    ) external;

    /// @notice Manages rewards for `user`, used at the beginning
    ///         of some external strategy for `user`.
    /// @dev Be extremely careful giving this authority to anyone, the
    ///      intention is to allow delegate claim functionality to hot wallets
    ///      or strategies that make sure of rewards directly without
    ///      distributing rewards to a user directly.
    ///      Emits a {ClaimApproval} event.
    /// @param user The address of the user having rewards managed.
    /// @param epochs The number of epochs for which to manage rewards.
    function manageRewardsFor(
        address user,
        uint256 epochs
    ) external returns (uint256);

    /// @notice Checks if a user has any CVE locker rewards to claim.
    /// @dev Even if a users lock is expiring the next lock resulting
    ///      in 0 points, we want their data updated so data is properly
    ///      adjusted on unlock.
    /// @param user The address of the user to check for reward claims.
    /// @return A boolean value indicating if the user has any rewards
    ///         to claim.
    function hasRewardsToClaim(address user) external view returns (bool);

    /// @notice Checks if a user has any CVE locker rewards to claim.
    /// @dev Even if a users lock is expiring the next lock resulting
    ///      in 0 points, we want their data updated so data is properly
    ///      adjusted on unlock.
    /// @param user The address of the user to check for reward claims.
    /// @return A value indicating if the user has any rewards to claim.
    function epochsToClaim(address user) external view returns (uint256);

    /// @notice Whether the CVE Locker is shut down or not.
    /// @dev 2 = yes; 1 = no.
    function isShutdown() external view returns (uint256);

    /// @notice Shuts down the CVELocker and prevents future reward
    /// distributions.
    /// @dev Should only be used to facilitate migration to a new system.
    function notifyLockerShutdown() external;
}
