// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

interface ICVXLocker {
    /// @notice Locks CVX as vlCVX on behalf of account
    function lock(
        address account,
        uint256 amount,
        uint256 spendRatio
    ) external;
}
