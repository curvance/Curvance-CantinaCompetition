// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @notice Rewards data for CVE rewards locker
 * @param _desiredRewardToken The token to receive as rewards.
 * @param _shouldLock Indicator of whether rewards should be locked, if applicable.
 * @param _isFreshLock Indicator of whether it's a fresh lock, if applicable.
 * @param _isFreshLockContinuous Indicator of whether the fresh lock should be continuous.
 */
struct rewardsData {
    address desiredRewardToken;
    bool shouldLock;
    bool isFreshLock;
    bool isFreshLockContinuous;
}

interface ICveLocker {
    // notice Update user claim index
    function updateUserClaimIndex(address _user, uint256 _index) external;
    // notice Reset user claim index
    function resetUserClaimIndex(address _user) external;
    
    // Claims a users veCVE rewards, only callable by veCVE contract
    function claimRewardsFor(
        address _user, 
        address _recipient,
        uint256 epoches,
        rewardsData memory _rewardsData,
        bytes memory params,
        uint256 _aux
    ) external;

    // Checks if a user has any CVE locker rewards to claim.
    function hasRewardsToClaim(address _user) external view returns (bool);

    // Checks how many epoches of CVE locker rewards a user has.
    function epochsToClaim(address _user) external view returns (uint256);

}
