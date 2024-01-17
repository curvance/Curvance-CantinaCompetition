// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseOracleRouter } from "../TestBaseOracleRouter.sol";
import { OracleRouter } from "contracts/oracles/OracleRouter.sol";

contract ReplaceAssetPriceFeedTest is TestBaseOracleRouter {
    function test_replaceAssetPriceFeed_fail_whenCallerIsNotAuthorized() public {
        _addSinglePriceFeed();
        
        vm.prank(address(1));

        vm.expectRevert(OracleRouter.OracleRouter__Unauthorized.selector);
        oracleRouter.replaceAssetPriceFeed(
            _USDC_ADDRESS,
            address(chainlinkAdaptor),
            address(dualChainlinkAdaptor)
        );
    }

    function test_replaceAssetPriceFeed_fail_whenAdaptorIsNotApproved() public {
        _addSinglePriceFeed();
        oracleRouter.removeApprovedAdaptor(address(dualChainlinkAdaptor));

        vm.expectRevert(OracleRouter.OracleRouter__InvalidParameter.selector);
        oracleRouter.replaceAssetPriceFeed(
            _USDC_ADDRESS,
            address(chainlinkAdaptor),
            address(dualChainlinkAdaptor)
        );
    }

    function test_replaceAssetPriceFeed_fail_whenNoFeedIsConfigured()
        public
    {

        vm.expectRevert(OracleRouter.OracleRouter__NotSupported.selector);
        oracleRouter.replaceAssetPriceFeed(
            _USDC_ADDRESS,
            address(chainlinkAdaptor),
            address(dualChainlinkAdaptor)
        );
    }

    function test_replaceAssetPriceFeed_fail_whenFeedsAreIdentical() public {
        _addSinglePriceFeed();

        vm.expectRevert(OracleRouter.OracleRouter__InvalidParameter.selector);
        oracleRouter.replaceAssetPriceFeed(
            _USDC_ADDRESS,
            address(chainlinkAdaptor),
            address(chainlinkAdaptor)
        );
    }

    function test_replaceAssetPriceFeed_fail_whenAssetIsNotSupported() public {
        _addDualPriceFeed();

        oracleRouter.addAssetPriceFeed(
            _USDC_ADDRESS,
            address(chainlinkAdaptor)
        );

        dualChainlinkAdaptor.removeAsset(_USDC_ADDRESS);

        vm.expectRevert(OracleRouter.OracleRouter__InvalidParameter.selector);
        oracleRouter.replaceAssetPriceFeed(
            _USDC_ADDRESS,
            address(chainlinkAdaptor),
            address(dualChainlinkAdaptor)
        );
    }

    function test_replaceAssetPriceFeed_success() public {
        vm.expectRevert();
        oracleRouter.assetPriceFeeds(_USDC_ADDRESS, 0);

        vm.expectRevert();
        oracleRouter.assetPriceFeeds(_USDC_ADDRESS, 1);

        _addSinglePriceFeed();

        assertEq(
            oracleRouter.assetPriceFeeds(_USDC_ADDRESS, 0),
            address(chainlinkAdaptor)
        );

        assertTrue(oracleRouter.isSupportedAsset(_USDC_ADDRESS));

        oracleRouter.replaceAssetPriceFeed(
            _USDC_ADDRESS,
            address(chainlinkAdaptor),
            address(dualChainlinkAdaptor)
        );

        assertEq(
            oracleRouter.assetPriceFeeds(_USDC_ADDRESS, 0),
            address(dualChainlinkAdaptor)
        );
        assertTrue(oracleRouter.isSupportedAsset(_USDC_ADDRESS));
    }
}
