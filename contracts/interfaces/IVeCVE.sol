// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

import "contracts/interfaces/ICveLocker.sol";

interface IVeCVE {
    // @notice Sends CVE to a desired destination chain
    function lockFor(
        address _recipient,
        uint256 _amount,
        bool _continuousLock,
        address _rewardRecipient,
        rewardsData memory _rewardsData,
        bytes memory _params,
        uint256 _aux
    ) external;

    // @notice Sends CVE Gauge Emissions to a desired destination chain
    function increaseAmountAndExtendLockFor(
        address _recipient,
        uint256 _amount,
        uint256 _lockIndex,
        bool _continuousLock,
        address _rewardRecipient,
        rewardsData memory _rewardsData,
        bytes memory _params,
        uint256 _aux
    ) external;

    // @notice Returns a user's current token points for 
    function userTokenPoints(address _user) external view returns (uint256);

    // @notice Returns a user's token unlocks for an epoch
    function userTokenUnlocksByEpoch(address _user, uint256 _epoch) external view returns (uint256);

    // @notice Updates user points by reducing the amount that gets unlocked in a specific epoch.
    function updateUserPoints(address _user, uint256 _epoch) external;

    // @notice Returns the timestamp of when the next epoch begins
    function nextEpochStartTime() external view returns (uint256);

}
