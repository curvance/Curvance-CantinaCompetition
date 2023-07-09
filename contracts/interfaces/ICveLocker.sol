// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ICveLocker {
<<<<<<< HEAD
    // notice Update user claim index
    function updateUserClaimIndex(address _user, uint256 _index) external;
    // notice Reset user claim index
    function resetUserClaimIndex(address _user) external;
    
    // Claims a users veCVE rewards, only callable by veCVE contract
=======
    /// @notice Update user claim index
    function updateUserClaimIndex(address _user, uint256 _index) external;

    /// @notice Reset user claim index
    function resetUserClaimIndex(address _user) external;

    /// @notice Claims a users veCVE rewards, only callable by veCVE contract
>>>>>>> 91b273c (adjust length of comments)
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
<<<<<<< HEAD

    // Checks if a user has any CVE locker rewards to claim and returns how many epochs a user has rewards for.
    function hasRewardsToClaim(address _user) external view returns (bool, uint256);

=======
>>>>>>> 91b273c (adjust length of comments)
}
