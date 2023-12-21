// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBasePriceRouter } from "../TestBasePriceRouter.sol";
import { IChainlink } from "contracts/interfaces/external/chainlink/IChainlink.sol";
import { PriceRouter } from "contracts/oracles/PriceRouter.sol";

contract GetPriceTest is TestBasePriceRouter {
    function test_getPrice_fail_whenNoFeedsAvailable() public {
        vm.expectRevert(PriceRouter.PriceRouter__NotSupported.selector);
        priceRouter.getPrice(_USDC_ADDRESS, true, true);
    }

    function test_getPrice_success_withBadSourceErrorCode_whenSequencerIsDown()
        public
    {
        _addSinglePriceFeed();
        sequencer.setMockAnswer(1);

        (uint256 price, uint256 errorCode) = priceRouter.getPrice(
            _USDC_ADDRESS,
            true,
            true
        );
        assertEq(price, 0);
        assertEq(errorCode, priceRouter.BAD_SOURCE());
    }

    function test_getPrice_fail_withBadSourceErrorCode_whenGracePeriodNotOver()
        public
    {
        _addSinglePriceFeed();
        sequencer.setMockStartedAt(block.timestamp);

        (uint256 price, uint256 errorCode) = priceRouter.getPrice(
            _USDC_ADDRESS,
            true,
            true
        );
        assertEq(price, 0);
        assertEq(errorCode, priceRouter.BAD_SOURCE());
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
