// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBase } from "tests/utils/TestBase.sol";

import { SavingsDaiAggregator } from "contracts/oracles/adaptors/wrappedAggregators/SavingsDaiAggregator.sol";
import { IChainlink } from "contracts/interfaces/external/chainlink/IChainlink.sol";
import { IPotLike } from "contracts/interfaces/external/maker/IPotLike.sol";
import { ISavingsDai } from "contracts/interfaces/external/maker/ISavingsDai.sol";

contract TestSavingsDaiAggregator is TestBase {
    address private SDAI = 0x83F20F44975D03b1b09e64809B757c47f942BEeA;
    address private DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    address private CHAINLINK_PRICE_FEED_DAI =
        0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;

    SavingsDaiAggregator public aggregator;

    function setUp() public {
        _fork();

        aggregator = new SavingsDaiAggregator(
            SDAI,
            DAI,
            CHAINLINK_PRICE_FEED_DAI
        );
    }

    function testMinMaxAnswer() public {
        int192 maxAnswer = aggregator.maxAnswer();
        int192 minAnswer = aggregator.minAnswer();
        assertGt(maxAnswer, minAnswer);
    }

    function testLatestRoundData() public {
        (, int256 sdaiPrice, , , ) = aggregator.latestRoundData();
        (, int256 daiPrice, , , ) = IChainlink(CHAINLINK_PRICE_FEED_DAI)
            .latestRoundData();
        assertEq(
            uint256(sdaiPrice),
            ((uint256(daiPrice) * IPotLike(ISavingsDai(SDAI).pot()).chi()) /
                1e9) / 1e18
        );
    }
}
