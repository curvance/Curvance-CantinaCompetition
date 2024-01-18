// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBase } from "tests/utils/TestBase.sol";

import { WstETHAggregator } from "contracts/oracles/adaptors/wrappedAggregators/WstETHAggregator.sol";
import { IChainlink } from "contracts/interfaces/external/chainlink/IChainlink.sol";
import { IWstETH } from "contracts/interfaces/external/wsteth/IWstETH.sol";

contract TestWstETHAggregator is TestBase {
    address private WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address private STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    address private CHAINLINK_PRICE_FEED_STETH =
        0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8;

    WstETHAggregator public aggregator;

    function setUp() public {
        _fork(18031848);

        aggregator = new WstETHAggregator(
            WSTETH,
            STETH,
            CHAINLINK_PRICE_FEED_STETH
        );
    }

    function testMinMaxAnswer() public {
        int192 maxAnswer = aggregator.maxAnswer();
        int192 minAnswer = aggregator.minAnswer();
        assertGt(maxAnswer, minAnswer);
    }

    function testLatestRoundData() public {
        (, int256 wstethPrice, , , ) = aggregator.latestRoundData();
        (, int256 stethPrice, , , ) = IChainlink(CHAINLINK_PRICE_FEED_STETH)
            .latestRoundData();
        assertEq(
            uint256(wstethPrice),
            (uint256(stethPrice) * IWstETH(WSTETH).getStETHByWstETH(1e18)) /
                1e18
        );
    }
}
