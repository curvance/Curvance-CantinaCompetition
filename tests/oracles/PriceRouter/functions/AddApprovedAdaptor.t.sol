// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBasePriceRouter } from "../TestBasePriceRouter.sol";
import { PriceRouter } from "contracts/oracles/PriceRouter.sol";

contract AddApprovedAdaptorTest is TestBasePriceRouter {
    function test_addApprovedAdaptor_fail_whenCallerIsNotAuthorized() public {
        vm.prank(address(1));

        vm.expectRevert(PriceRouter.PriceRouter__Unauthorized.selector);
        priceRouter.addApprovedAdaptor(address(chainlinkAdaptor));
    }

    function test_addApprovedAdaptor_fail_whenAdaptorIsAlreadyConfigured()
        public
    {
        priceRouter.addApprovedAdaptor(address(chainlinkAdaptor));

        vm.expectRevert(PriceRouter.PriceRouter__InvalidParameter.selector);
        priceRouter.addApprovedAdaptor(address(chainlinkAdaptor));
    }

    function test_addApprovedAdaptor_success() public {
        assertFalse(priceRouter.isApprovedAdaptor(address(chainlinkAdaptor)));

        priceRouter.addApprovedAdaptor(address(chainlinkAdaptor));

        assertTrue(priceRouter.isApprovedAdaptor(address(chainlinkAdaptor)));
    }
}
