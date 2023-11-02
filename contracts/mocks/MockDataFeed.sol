// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import { IChainlink } from "contracts/interfaces/external/chainlink/IChainlink.sol";

contract MockDataFeed {
    int256 public mockAnswer;
    uint256 public mockStartedAt;
    uint256 public mockUpdatedAt;

    IChainlink public immutable realFeed;

    constructor(address realFeed_) {
        realFeed = IChainlink(realFeed_);
    }

    function aggregator() external view returns (address) {
        return realFeed.aggregator();
    }

    function decimals() external view returns (uint8) {
        return realFeed.decimals();
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
        if (address(realFeed) != address(0)) {
            (roundId, answer, startedAt, updatedAt, answeredInRound) = realFeed
                .latestRoundData();
        }
        if (mockAnswer != 0) answer = mockAnswer;
        if (mockStartedAt != 0) startedAt = mockStartedAt;
        if (mockUpdatedAt != 0) updatedAt = mockUpdatedAt;
    }

    function setMockAnswer(int256 ans) external {
        mockAnswer = ans;
    }

    function setMockStartedAt(uint256 at) external {
        mockStartedAt = at;
    }

    function setMockUpdatedAt(uint256 at) external {
        mockUpdatedAt = at;
    }
}
