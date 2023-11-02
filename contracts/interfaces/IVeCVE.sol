// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

import { RewardsData } from "contracts/interfaces/ICVELocker.sol";

interface IVeCVE {
    /// @notice Sends CVE to a desired destination chain
    function createLockFor(
        address recipient,
        uint256 amount,
        bool continuousLock,
        RewardsData memory rewardsData,
        bytes memory params,
        uint256 aux
    ) external;

    /// @notice Sends CVE Gauge Emissions to a desired destination chain
    function increaseAmountAndExtendLockFor(
        address recipient,
        uint256 amount,
        uint256 lockIndex,
        bool continuousLock,
        RewardsData memory rewardsData,
        bytes memory params,
        uint256 aux
    ) external;

    /// @notice Returns the chain's current token points for
    function chainPoints() external view returns (uint256);

    /// @notice Returns the chain's token unlocks for an epoch
    function chainUnlocksByEpoch(
        uint256 epoch
    ) external view returns (uint256);

    /// @notice Returns a user's current token points for
    function userPoints(address user) external view returns (uint256);

    /// @notice Returns a user's token unlocks for an epoch
    function userUnlocksByEpoch(
        address user,
        uint256 epoch
    ) external view returns (uint256);

    /// @notice Updates user points by reducing the amount
    ///         that gets unlocked in a specific epoch.
    function updateUserPoints(address user, uint256 epoch) external;

    /// @notice Returns the timestamp of when the next epoch begins
    function nextEpochStartTime() external view returns (uint256);
}
