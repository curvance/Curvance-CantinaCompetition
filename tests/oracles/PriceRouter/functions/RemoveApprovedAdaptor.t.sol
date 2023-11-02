// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBasePriceRouter } from "../TestBasePriceRouter.sol";
import { PriceRouter } from "contracts/oracles/PriceRouter.sol";

contract RemoveApprovedAdaptorTest is TestBasePriceRouter {
    function test_removeApprovedAdaptor_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.prank(address(1));

        vm.expectRevert(PriceRouter.PriceRouter__Unauthorized.selector);
        priceRouter.removeApprovedAdaptor(address(chainlinkAdaptor));
    }

    function test_removeApprovedAdaptor_fail_whenAdaptorDoesNotExist() public {
        vm.expectRevert(PriceRouter.PriceRouter__InvalidParameter.selector);
        priceRouter.removeApprovedAdaptor(address(chainlinkAdaptor));
    }

    function test_removeApprovedAdaptor_success() public {
        priceRouter.addApprovedAdaptor(address(chainlinkAdaptor));

        assertTrue(priceRouter.isApprovedAdaptor(address(chainlinkAdaptor)));

        priceRouter.removeApprovedAdaptor(address(chainlinkAdaptor));

        assertFalse(priceRouter.isApprovedAdaptor(address(chainlinkAdaptor)));
    }
}
