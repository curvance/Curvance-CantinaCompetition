// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBasePriceRouter } from "../TestBasePriceRouter.sol";
import { PriceRouter } from "contracts/oracles/PriceRouter.sol";

contract SetChainlinkDelayTest is TestBasePriceRouter {
    function test_setChainlinkDelay_fail_whenCallerIsNotAuthorized() public {
        vm.prank(address(1));

        vm.expectRevert(PriceRouter.PriceRouter__Unauthorized.selector);
        priceRouter.setChainlinkDelay(0.5 days);
    }

    function test_setChainlinkDelay_fail_whenDelayIsTooLarge() public {
        vm.expectRevert(PriceRouter.PriceRouter__InvalidParameter.selector);
        priceRouter.setChainlinkDelay(1 days + 1);
    }

    function test_setChainlinkDelay_success() public {
        assertEq(priceRouter.CHAINLINK_MAX_DELAY(), 1 days);

        priceRouter.setChainlinkDelay(0.5 days);

        assertEq(priceRouter.CHAINLINK_MAX_DELAY(), 0.5 days);
    }
}
