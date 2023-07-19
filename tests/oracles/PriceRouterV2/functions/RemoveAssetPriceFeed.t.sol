// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBasePriceRouterV2 } from "../TestBasePriceRouterV2.sol";

contract RemoveAssetPriceFeedTest is TestBasePriceRouterV2 {
    function test_removeAssetPriceFeed_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.prank(address(1));

        vm.expectRevert("centralRegistry: UNAUTHORIZED");
        priceRouter.removeAssetPriceFeed(
            _USDC_ADDRESS,
            address(chainlinkAdaptor)
        );
    }

    function test_removeAssetPriceFeed_fail_whenNoFeedsAvailable() public {
        vm.expectRevert("priceRouter: no feeds available");
        priceRouter.removeAssetPriceFeed(
            _USDC_ADDRESS,
            address(chainlinkAdaptor)
        );
    }

    function test_removeAssetPriceFeed_fail_whenSingleFeedDoesNotExist()
        public
    {
        _addSinglePriceFeed();

        vm.expectRevert("priceRouter: feed does not exist");
        priceRouter.removeAssetPriceFeed(_USDC_ADDRESS, address(1));
    }

    function test_removeAssetPriceFeed_fail_whenDualFeedDoesNotExist() public {
        _addDualPriceFeed();

        vm.expectRevert("priceRouter: feed does not exist");
        priceRouter.removeAssetPriceFeed(_USDC_ADDRESS, address(1));
    }

    function test_removeAssetPriceFeed_success_whenRemoveSingleFeed() public {
        _addSinglePriceFeed();

        assertEq(
            priceRouter.assetPriceFeeds(_USDC_ADDRESS, 0),
            address(chainlinkAdaptor)
        );

        priceRouter.removeAssetPriceFeed(
            _USDC_ADDRESS,
            address(chainlinkAdaptor)
        );

        vm.expectRevert();
        priceRouter.assetPriceFeeds(_USDC_ADDRESS, 0);
    }

    function test_removeAssetPriceFeed_success_whenRemoveDualFeed() public {
        _addDualPriceFeed();

        assertEq(
            priceRouter.assetPriceFeeds(_USDC_ADDRESS, 0),
            address(chainlinkAdaptor)
        );
        assertEq(
            priceRouter.assetPriceFeeds(_USDC_ADDRESS, 1),
            address(dualChainlinkAdaptor)
        );

        priceRouter.removeAssetPriceFeed(
            _USDC_ADDRESS,
            address(chainlinkAdaptor)
        );

        assertEq(
            priceRouter.assetPriceFeeds(_USDC_ADDRESS, 0),
            address(dualChainlinkAdaptor)
        );

        vm.expectRevert();
        priceRouter.assetPriceFeeds(_USDC_ADDRESS, 1);
    }
}
