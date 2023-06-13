// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

interface IVeCVE {
    // @notice Sends CVE to a desired destination chain
    function lockFor (address _recipient, uint256 _amount, bool _continuousLock)  external;
    // @notice Sends CVE Gauge Emissions to a desired destination chain
    function increaseAmountAndExtendLockFor(address _recipient, uint256 _amount, uint256 _lockIndex, bool _continuousLock) external;
}
