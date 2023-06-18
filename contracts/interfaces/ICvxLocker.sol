// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

interface ICVXLocker {
    // @notice Locks CVX as vlCVX on behalf of _account
    function lock(address _account, uint256 _amount, uint256 _spendRatio) external;
}
