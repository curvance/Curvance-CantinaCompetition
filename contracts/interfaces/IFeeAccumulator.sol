// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

struct EpochRolloverData {
        uint256 chainId;
        uint256 value;
        uint256 numChainData;
        uint256 epoch;
    }

interface IFeeAccumulator {

    /// @notice Returns stargate router address
    function router() external view returns (address);
    /// @notice Receive finalized epoch rewards data
    function receiveExecutableLockData(uint256 lockValue) external;
    /// @notice Receive feeAccumulator information of locked tokens on a chain for the epoch
    function receiveCrossChainLockData(EpochRolloverData memory data) external;
}
