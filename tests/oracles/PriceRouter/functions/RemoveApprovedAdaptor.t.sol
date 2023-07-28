// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBasePriceRouter } from "../TestBasePriceRouter.sol";

contract RemoveApprovedAdaptorTest is TestBasePriceRouter {
    function test_removeApprovedAdaptor_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.prank(address(1));

        vm.expectRevert("centralRegistry: UNAUTHORIZED");
        priceRouter.removeApprovedAdaptor(address(chainlinkAdaptor));
    }

    function test_removeApprovedAdaptor_fail_whenAdaptorDoesNotExist() public {
        vm.expectRevert("PriceRouter: adaptor does not exist");
        priceRouter.removeApprovedAdaptor(address(chainlinkAdaptor));
    }

    function test_removeApprovedAdaptor_success() public {
        priceRouter.addApprovedAdaptor(address(chainlinkAdaptor));

        assertTrue(priceRouter.isApprovedAdaptor(address(chainlinkAdaptor)));

        priceRouter.removeApprovedAdaptor(address(chainlinkAdaptor));

        assertFalse(priceRouter.isApprovedAdaptor(address(chainlinkAdaptor)));
    }
}
