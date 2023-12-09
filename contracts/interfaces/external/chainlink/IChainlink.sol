// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

interface IChainlink {
    /// @notice Returns the maximum value that the aggregator can returned
    function maxAnswer() external view returns (int192);

    /// @notice Returns the minimum value that the aggregator can returned
    function minAnswer() external view returns (int192);

    /// @notice Returns the current phase's aggregator address.
    function aggregator() external view returns (address);

    /// @notice Returns the number of decimals the aggregator responses with.
    function decimals() external view returns (uint8);

    function latestRoundData() external view returns (
        uint80 roundId, 
        int256 answer, 
        uint256 startedAt, 
        uint256 updatedAt, 
        uint80 answeredInRound
    );
}
