// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseOracleRouter } from "../TestBaseOracleRouter.sol";
import { OracleRouter } from "contracts/oracles/OracleRouter.sol";

contract RemoveAssetPriceFeedTest is TestBaseOracleRouter {
    function test_removeAssetPriceFeed_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.prank(address(1));

        vm.expectRevert(OracleRouter.OracleRouter__Unauthorized.selector);
        oracleRouter.removeAssetPriceFeed(
            _USDC_ADDRESS,
            address(chainlinkAdaptor)
        );
    }

    function test_removeAssetPriceFeed_fail_whenNoFeedsAvailable() public {
        vm.expectRevert(OracleRouter.OracleRouter__NotSupported.selector);
        oracleRouter.removeAssetPriceFeed(
            _USDC_ADDRESS,
            address(chainlinkAdaptor)
        );
    }

    function test_removeAssetPriceFeed_fail_whenSingleFeedDoesNotExist()
        public
    {
        _addSinglePriceFeed();

        vm.expectRevert(OracleRouter.OracleRouter__NotSupported.selector);
        oracleRouter.removeAssetPriceFeed(_USDC_ADDRESS, address(1));
    }

    function test_removeAssetPriceFeed_fail_whenDualFeedDoesNotExist() public {
        _addDualPriceFeed();

        vm.expectRevert(OracleRouter.OracleRouter__NotSupported.selector);
        oracleRouter.removeAssetPriceFeed(_USDC_ADDRESS, address(1));
    }

    function test_removeAssetPriceFeed_success_whenRemoveSingleFeed() public {
        _addSinglePriceFeed();

        assertEq(
            oracleRouter.assetPriceFeeds(_USDC_ADDRESS, 0),
            address(chainlinkAdaptor)
        );

        oracleRouter.removeAssetPriceFeed(
            _USDC_ADDRESS,
            address(chainlinkAdaptor)
        );

        vm.expectRevert();
        oracleRouter.assetPriceFeeds(_USDC_ADDRESS, 0);
    }

    function test_removeAssetPriceFeed_success_whenRemoveDualFeed() public {
        _addDualPriceFeed();

        assertEq(
            oracleRouter.assetPriceFeeds(_USDC_ADDRESS, 0),
            address(chainlinkAdaptor)
        );
        assertEq(
            oracleRouter.assetPriceFeeds(_USDC_ADDRESS, 1),
            address(dualChainlinkAdaptor)
        );

        oracleRouter.removeAssetPriceFeed(
            _USDC_ADDRESS,
            address(chainlinkAdaptor)
        );

        assertEq(
            oracleRouter.assetPriceFeeds(_USDC_ADDRESS, 0),
            address(dualChainlinkAdaptor)
        );

        vm.expectRevert();
        oracleRouter.assetPriceFeeds(_USDC_ADDRESS, 1);
    }
}
