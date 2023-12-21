// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ICVXLocker {
    /// @notice Locks CVX as vlCVX on behalf of account
    function lock(
        address account,
        uint256 amount,
        uint256 spendRatio
    ) external;

    /// @notice Returns whether the locker is shutdown or not
    function isShutdown() external view returns (bool);
    /// @notice Returns the staking token for the locker
    function stakingToken() external view returns (address);
}
