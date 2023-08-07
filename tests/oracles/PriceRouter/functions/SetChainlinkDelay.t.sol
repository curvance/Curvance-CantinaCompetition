// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBasePriceRouter } from "../TestBasePriceRouter.sol";

contract SetChainlinkDelayTest is TestBasePriceRouter {
    function test_setChainlinkDelay_fail_whenCallerIsNotAuthorized() public {
        vm.prank(address(1));

        vm.expectRevert("centralRegistry: UNAUTHORIZED");
        priceRouter.setChainlinkDelay(0.5 days);
    }

    function test_setChainlinkDelay_fail_whenDelayIsTooLarge() public {
        vm.expectRevert("PriceRouter: delay is too large");
        priceRouter.setChainlinkDelay(1 days);
    }

    function test_setChainlinkDelay_success() public {
        assertEq(priceRouter.CHAINLINK_MAX_DELAY(), 1 days);

        priceRouter.setChainlinkDelay(0.5 days);

        assertEq(priceRouter.CHAINLINK_MAX_DELAY(), 0.5 days);
    }
}
