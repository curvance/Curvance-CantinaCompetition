// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBasePriceRouter } from "../TestBasePriceRouter.sol";
import { IChainlink } from "contracts/interfaces/external/chainlink/IChainlink.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { ChainlinkAdaptor } from "contracts/oracles/adaptors/chainlink/ChainlinkAdaptor.sol";
import { PriceRouter } from "contracts/oracles/PriceRouter.sol";
import { MockDataFeed } from "contracts/mocks/MockDataFeed.sol";

contract GetPriceTest is TestBasePriceRouter {
    MockDataFeed public sequencer;

    function setUp() public override {
        super.setUp();

        sequencer = new MockDataFeed(address(0));

        chainlinkAdaptor = new ChainlinkAdaptor(
            ICentralRegistry(address(centralRegistry)),
            address(sequencer)
        );

        chainlinkAdaptor.addAsset(_USDC_ADDRESS, _CHAINLINK_USDC_USD, true);
        chainlinkAdaptor.addAsset(_USDC_ADDRESS, _CHAINLINK_USDC_ETH, false);
    }

    function test_getPrice_fail_whenNoFeedsAvailable() public {
        vm.expectRevert(PriceRouter.PriceRouter__NotSupported.selector);
        priceRouter.getPrice(_USDC_ADDRESS, true, true);
    }

    function test_getPrice_fail_whenSequencerIsDown() public {
        _addSinglePriceFeed();
        sequencer.setMockAnswer(1);

        vm.expectRevert(
            ChainlinkAdaptor.ChainlinkAdaptor__SequencerIsDown.selector
        );
        priceRouter.getPrice(_USDC_ADDRESS, true, true);
    }

    function test_getPrice_fail_whenGracePeriodNotOver() public {
        _addSinglePriceFeed();
        sequencer.setMockStartedAt(block.timestamp);

        vm.expectRevert(
            ChainlinkAdaptor.ChainlinkAdaptor__GracePeriodNotOver.selector
        );
        priceRouter.getPrice(_USDC_ADDRESS, true, true);
    }

    function test_getPrice_success() public {
        _addSinglePriceFeed();

        (, int256 usdcPrice, , , ) = IChainlink(_CHAINLINK_USDC_USD)
            .latestRoundData();

        (uint256 price, uint256 errorCode) = priceRouter.getPrice(
            _USDC_ADDRESS,
            true,
            true
        );

        assertEq(price, uint256(usdcPrice) * 1e10);
        assertEq(errorCode, 0);

        (, int256 ethPrice, , , ) = IChainlink(_CHAINLINK_USDC_ETH)
            .latestRoundData();

        (price, errorCode) = priceRouter.getPrice(_USDC_ADDRESS, false, true);

        assertEq(price, uint256(ethPrice));
        assertEq(errorCode, 0);
    }
}
