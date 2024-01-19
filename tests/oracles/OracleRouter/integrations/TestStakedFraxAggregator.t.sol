// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBase } from "tests/utils/TestBase.sol";

import { StakedFraxAggregator } from "contracts/oracles/adaptors/wrappedAggregators/StakedFraxAggregator.sol";
import { IChainlink } from "contracts/interfaces/external/chainlink/IChainlink.sol";
import { IStakedFrax } from "contracts/interfaces/external/frax/IStakedFrax.sol";

contract TestStakedFraxAggregator is TestBase {
    address private SFRAX = 0xA663B02CF0a4b149d2aD41910CB81e23e1c41c32;
    address private FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e;

    address private CHAINLINK_PRICE_FEED_FRAX =
        0xB9E1E3A9feFf48998E45Fa90847ed4D467E8BcfD;

    StakedFraxAggregator public aggregator;

    function setUp() public {
        _fork();

        aggregator = new StakedFraxAggregator(
            SFRAX,
            FRAX,
            CHAINLINK_PRICE_FEED_FRAX
        );
    }

    function testMinMaxAnswer() public {
        int192 maxAnswer = aggregator.maxAnswer();
        int192 minAnswer = aggregator.minAnswer();
        assertGt(maxAnswer, minAnswer);
    }

    function testLatestRoundData() public {
        (, int256 sfraxPrice, , , ) = aggregator.latestRoundData();
        (, int256 fraxPrice, , , ) = IChainlink(CHAINLINK_PRICE_FEED_FRAX)
            .latestRoundData();
        assertEq(
            uint256(sfraxPrice),
            (uint256(fraxPrice) * IStakedFrax(SFRAX).pricePerShare()) / 1e18
        );
    }
}
