// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import { IChainlinkAggregator } from "contracts/interfaces/external/chainlink/IChainlinkAggregator.sol";

contract MockDataFeed {
    int256 public mockAnswer;
    uint256 public mockUpdatedAt;

    IChainlinkAggregator public immutable realFeed;

    constructor(address _realFeed) {
        realFeed = IChainlinkAggregator(_realFeed);
    }

    function aggregator() external view returns (address) {
        return realFeed.aggregator();
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        (roundId, answer, startedAt, updatedAt, answeredInRound) = realFeed
            .latestRoundData();
        if (mockAnswer != 0) answer = mockAnswer;
        if (mockUpdatedAt != 0) updatedAt = mockUpdatedAt;
    }

    function setMockAnswer(int256 ans) external {
        mockAnswer = ans;
    }

    function setMockUpdatedAt(uint256 at) external {
        mockUpdatedAt = at;
    }
}
