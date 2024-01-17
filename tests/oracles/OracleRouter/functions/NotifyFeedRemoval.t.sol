// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseOracleRouter } from "../TestBaseOracleRouter.sol";
import { OracleRouter } from "contracts/oracles/OracleRouter.sol";

contract NotifyFeedRemovalTest is TestBaseOracleRouter {
    function test_notifyFeedRemoval_fail_whenCallerIsNotApprovedAdaptor()
        public
    {
        vm.expectRevert(OracleRouter.OracleRouter__Unauthorized.selector);
        oracleRouter.notifyFeedRemoval(_USDC_ADDRESS);
    }

    function test_notifyFeedRemoval_fail_whenNoFeedsAvailable() public {
        oracleRouter.addApprovedAdaptor(address(chainlinkAdaptor));

        vm.prank(address(chainlinkAdaptor));

        vm.expectRevert(OracleRouter.OracleRouter__NotSupported.selector);
        oracleRouter.notifyFeedRemoval(_USDC_ADDRESS);
    }

    function test_notifyFeedRemoval_fail_whenSingleFeedDoesNotExist() public {
        _addSinglePriceFeed();

        oracleRouter.addApprovedAdaptor(address(dualChainlinkAdaptor));

        vm.prank(address(dualChainlinkAdaptor));

        vm.expectRevert(OracleRouter.OracleRouter__NotSupported.selector);
        oracleRouter.notifyFeedRemoval(_USDC_ADDRESS);
    }

    function test_notifyFeedRemoval_fail_whenDualFeedDoesNotExist() public {
        _addDualPriceFeed();

        oracleRouter.addApprovedAdaptor(address(1));

        vm.prank(address(1));

        vm.expectRevert(OracleRouter.OracleRouter__NotSupported.selector);
        oracleRouter.notifyFeedRemoval(_USDC_ADDRESS);
    }

    function test_notifyFeedRemoval_success_whenRemoveSingleFeed() public {
        _addSinglePriceFeed();

        assertEq(
            oracleRouter.assetPriceFeeds(_USDC_ADDRESS, 0),
            address(chainlinkAdaptor)
        );

        vm.prank(address(chainlinkAdaptor));
        oracleRouter.notifyFeedRemoval(_USDC_ADDRESS);

        vm.expectRevert();
        oracleRouter.assetPriceFeeds(_USDC_ADDRESS, 0);
    }

    function test_notifyFeedRemoval_success_whenRemoveDualFeed() public {
        _addDualPriceFeed();

        assertEq(
            oracleRouter.assetPriceFeeds(_USDC_ADDRESS, 0),
            address(chainlinkAdaptor)
        );
        assertEq(
            oracleRouter.assetPriceFeeds(_USDC_ADDRESS, 1),
            address(dualChainlinkAdaptor)
        );

        vm.prank(address(chainlinkAdaptor));
        oracleRouter.notifyFeedRemoval(_USDC_ADDRESS);

        assertEq(
            oracleRouter.assetPriceFeeds(_USDC_ADDRESS, 0),
            address(dualChainlinkAdaptor)
        );

        vm.expectRevert();
        oracleRouter.assetPriceFeeds(_USDC_ADDRESS, 1);
    }
}
