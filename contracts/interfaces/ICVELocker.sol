// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @notice Rewards data for CVE rewards locker
/// @param desiredRewardToken The token to receive as rewards.
/// @param shouldLock Indicator of whether rewards should be locked,
///                   if applicable.
/// @param isFreshLock Indicator of whether it's a fresh lock, if applicable.
/// @param isFreshLockContinuous Indicator of whether the fresh lock
///                              should be continuous.
struct RewardsData {
    address desiredRewardToken;
    bool shouldLock;
    bool isFreshLock;
    bool isFreshLockContinuous;
}

interface ICVELocker {

    /// @notice Called by Fee Accumulator to record an epochs rewards
    function recordEpochRewards(uint256 epoch, uint256 rewardsPerCVE) external;

    /// @notice Returns the current epoch for `time`
    function currentEpoch(uint256 time) external view returns (uint256);

    /// @notice Returns the next undelivered epoch index
    function nextEpochToDeliver() external view returns (uint256);

    /// @notice Update user claim index
    function updateUserClaimIndex(address user, uint256 index) external;

    /// @notice Reset user claim index
    function resetUserClaimIndex(address user) external;

    /// @notice Claims a users VeCVE rewards, only callable by VeCVE contract
    function claimRewardsFor(
        address user,
        uint256 epoches,
        RewardsData memory rewardsData,
        bytes memory params,
        uint256 aux
    ) external;

    /// @notice Checks if a user has any CVE locker rewards to claim.
    function hasRewardsToClaim(address user) external view returns (bool);

    /// @notice Checks how many epoches of CVE locker rewards a user has.
    function epochsToClaim(address user) external view returns (uint256);

    /// @notice Allows VeCVE to shut down cve locker to prepare
    ///         for a new VeCVE locker
    function notifyLockerShutdown() external;
}
