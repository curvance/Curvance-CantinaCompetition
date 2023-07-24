// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @notice Rewards data for CVE rewards locker
 * @param _desiredRewardToken The token to receive as rewards.
 * @param _shouldLock Indicator of whether rewards should be locked, if applicable.
 * @param _isFreshLock Indicator of whether it's a fresh lock, if applicable.
 * @param _isFreshLockContinuous Indicator of whether the fresh lock should be continuous.
 */
struct RewardsData {
    address desiredRewardToken;
    bool shouldLock;
    bool isFreshLock;
    bool isFreshLockContinuous;
}

interface ICVELocker {
    /// notice Update user claim index
    function updateUserClaimIndex(address user, uint256 index) external;

    /// notice Reset user claim index
    function resetUserClaimIndex(address user) external;

    /// Claims a users VeCVE rewards, only callable by VeCVE contract
    function claimRewardsFor(
        address user,
        address recipient,
        uint256 epoches,
        RewardsData memory rewardsData,
        bytes memory params,
        uint256 aux
    ) external;

    /// Checks if a user has any CVE locker rewards to claim.
    function hasRewardsToClaim(address user) external view returns (bool);

    /// Checks how many epoches of CVE locker rewards a user has.
    function epochsToClaim(address user) external view returns (uint256);

    /// Allows VeCVE to shut down cve locker to prepare for a new VeCVE locker
    function notifyLockerShutdown() external;
}
