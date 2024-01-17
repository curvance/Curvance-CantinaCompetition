// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseOracleRouter } from "../TestBaseOracleRouter.sol";
import { OracleRouter } from "contracts/oracles/OracleRouter.sol";

contract AddAssetPriceFeedTest is TestBaseOracleRouter {
    function test_addAssetPriceFeed_fail_whenCallerIsNotAuthorized() public {
        vm.prank(address(1));

        vm.expectRevert(OracleRouter.OracleRouter__Unauthorized.selector);
        oracleRouter.addAssetPriceFeed(
            _USDC_ADDRESS,
            address(chainlinkAdaptor)
        );
    }

    function test_addAssetPriceFeed_fail_whenAdaptorIsNotApproved() public {
        vm.expectRevert(OracleRouter.OracleRouter__InvalidParameter.selector);
        oracleRouter.addAssetPriceFeed(
            _USDC_ADDRESS,
            address(chainlinkAdaptor)
        );
    }

    function test_addAssetPriceFeed_fail_whenDualFeedIsAlreadyConfigured()
        public
    {
        _addDualPriceFeed();

        vm.expectRevert(OracleRouter.OracleRouter__InvalidParameter.selector);
        oracleRouter.addAssetPriceFeed(
            _USDC_ADDRESS,
            address(dualChainlinkAdaptor)
        );
    }

    function test_addAssetPriceFeed_fail_whenFeedAlreadyAdded() public {
        _addSinglePriceFeed();

        vm.expectRevert(OracleRouter.OracleRouter__InvalidParameter.selector);
        oracleRouter.addAssetPriceFeed(
            _USDC_ADDRESS,
            address(chainlinkAdaptor)
        );
    }

    function test_addAssetPriceFeed_fail_whenAssetIsNotSupported() public {
        _addSinglePriceFeed();

        chainlinkAdaptor.removeAsset(_USDC_ADDRESS);

        vm.expectRevert(OracleRouter.OracleRouter__InvalidParameter.selector);
        oracleRouter.addAssetPriceFeed(
            _USDC_ADDRESS,
            address(chainlinkAdaptor)
        );
    }

    function test_addAssetPriceFeed_success() public {
        vm.expectRevert();
        oracleRouter.assetPriceFeeds(_USDC_ADDRESS, 0);

        vm.expectRevert();
        oracleRouter.assetPriceFeeds(_USDC_ADDRESS, 1);

        _addDualPriceFeed();

        assertEq(
            oracleRouter.assetPriceFeeds(_USDC_ADDRESS, 0),
            address(chainlinkAdaptor)
        );
        assertEq(
            oracleRouter.assetPriceFeeds(_USDC_ADDRESS, 1),
            address(dualChainlinkAdaptor)
        );

        assertTrue(oracleRouter.isSupportedAsset(_USDC_ADDRESS));
    }
}
