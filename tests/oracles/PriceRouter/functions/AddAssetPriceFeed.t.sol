// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBasePriceRouter } from "../TestBasePriceRouter.sol";

contract AddAssetPriceFeedTest is TestBasePriceRouter {
    function test_addAssetPriceFeed_fail_whenCallerIsNotAuthorized() public {
        vm.prank(address(1));

        vm.expectRevert("PriceRouter: UNAUTHORIZED");
        priceRouter.addAssetPriceFeed(
            _USDC_ADDRESS,
            address(chainlinkAdaptor)
        );
    }

    function test_addAssetPriceFeed_fail_whenAdaptorIsNotApproved() public {
        vm.expectRevert(0xebd2e1ff);
        priceRouter.addAssetPriceFeed(
            _USDC_ADDRESS,
            address(chainlinkAdaptor)
        );
    }

    function test_addAssetPriceFeed_fail_whenDualFeedIsAlreadyConfigured()
        public
    {
        _addDualPriceFeed();

        vm.expectRevert(0xebd2e1ff);
        priceRouter.addAssetPriceFeed(
            _USDC_ADDRESS,
            address(dualChainlinkAdaptor)
        );
    }

    function test_addAssetPriceFeed_fail_whenFeedAlreadyAdded() public {
        _addSinglePriceFeed();

        vm.expectRevert(0xebd2e1ff);
        priceRouter.addAssetPriceFeed(
            _USDC_ADDRESS,
            address(chainlinkAdaptor)
        );
    }

    function test_addAssetPriceFeed_fail_whenAssetIsNotSupported() public {
        _addSinglePriceFeed();

        chainlinkAdaptor.removeAsset(_USDC_ADDRESS);

        vm.expectRevert(0xebd2e1ff);
        priceRouter.addAssetPriceFeed(
            _USDC_ADDRESS,
            address(chainlinkAdaptor)
        );
    }

    function test_addAssetPriceFeed_success() public {
        vm.expectRevert();
        priceRouter.assetPriceFeeds(_USDC_ADDRESS, 0);

        vm.expectRevert();
        priceRouter.assetPriceFeeds(_USDC_ADDRESS, 1);

        _addDualPriceFeed();

        assertEq(
            priceRouter.assetPriceFeeds(_USDC_ADDRESS, 0),
            address(chainlinkAdaptor)
        );
        assertEq(
            priceRouter.assetPriceFeeds(_USDC_ADDRESS, 1),
            address(dualChainlinkAdaptor)
        );

        assertTrue(priceRouter.isSupportedAsset(_USDC_ADDRESS));
    }
}
