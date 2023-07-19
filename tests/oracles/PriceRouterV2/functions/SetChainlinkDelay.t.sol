// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBasePriceRouterV2 } from "../TestBasePriceRouterV2.sol";

contract SetChainlinkDelayTest is TestBasePriceRouterV2 {
    function test_setChainlinkDelay_fail_whenCallerIsNotAuthorized() public {
        vm.prank(address(1));

        vm.expectRevert("centralRegistry: UNAUTHORIZED");
        priceRouter.setChainlinkDelay(0.5 days);
    }

    function test_setChainlinkDelay_fail_whenDelayIsTooLarge() public {
        vm.expectRevert("priceRouter: delay is too large");
        priceRouter.setChainlinkDelay(1 days);
    }

    function test_setChainlinkDelay_success() public {
        assertEq(priceRouter.CHAINLINK_MAX_DELAY(), 1 days);

        priceRouter.setChainlinkDelay(0.5 days);

        assertEq(priceRouter.CHAINLINK_MAX_DELAY(), 0.5 days);
    }
}
