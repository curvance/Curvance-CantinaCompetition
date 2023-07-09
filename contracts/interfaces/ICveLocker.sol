// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

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
        address desiredRewardToken,
        bytes memory params,
        bool lock,
        bool isFreshLock,
        bool _continuousLock,
        uint256 _aux
    ) external;

    // Checks if a user has any CVE locker rewards to claim.
    function hasRewardsToClaim(address _user) external view returns (bool);

    // Checks how many epoches of CVE locker rewards a user has.
    function epochsToClaim(address _user) external view returns (uint256);

}
