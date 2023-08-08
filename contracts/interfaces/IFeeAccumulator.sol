// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

interface IFeeAccumulator {
    /// @notice Notifies the fee accumulator of tokens locked on another chain for the epoch
    function notifyCrossChainLockData(uint256 chainId, uint256 lockValue) external;
}
