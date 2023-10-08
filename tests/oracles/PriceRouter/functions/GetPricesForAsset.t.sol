// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import { TestBasePriceRouter } from "../TestBasePriceRouter.sol";
import { PriceRouter } from "contracts/oracles/PriceRouter.sol";

contract GetPricesForAssetTest is TestBasePriceRouter {
    function test_getPricesForAsset_fail_whenNoFeedsAvailable() public {
        vm.expectRevert(0xe4558fac);
        priceRouter.getPricesForAsset(_USDC_ADDRESS, true);
    }

    function test_getPricesForAsset_success() public {
        _addSinglePriceFeed();

        (, int256 usdcPrice, , , ) = AggregatorV3Interface(_CHAINLINK_USDC_USD)
            .latestRoundData();

        PriceRouter.FeedData[] memory feedDatas = priceRouter
            .getPricesForAsset(_USDC_ADDRESS, true);

        for (uint256 i = 0; i < feedDatas.length; i++) {
            assertEq(feedDatas[i].price, uint256(usdcPrice) * 1e10);
            assertFalse(feedDatas[i].hadError);
        }

        (, int256 ethPrice, , , ) = AggregatorV3Interface(_CHAINLINK_USDC_ETH)
            .latestRoundData();

        feedDatas = priceRouter.getPricesForAsset(_USDC_ADDRESS, false);

        for (uint256 i = 0; i < feedDatas.length; i++) {
            assertEq(feedDatas[i].price, uint256(ethPrice));
            assertFalse(feedDatas[i].hadError);
        }
    }
}
