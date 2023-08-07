// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBasePriceRouter } from "../TestBasePriceRouter.sol";

contract AddApprovedAdaptorTest is TestBasePriceRouter {
    function test_addApprovedAdaptor_fail_whenCallerIsNotAuthorized() public {
        vm.prank(address(1));

        vm.expectRevert("centralRegistry: UNAUTHORIZED");
        priceRouter.addApprovedAdaptor(address(chainlinkAdaptor));
    }

    function test_addApprovedAdaptor_fail_whenAdaptorIsAlreadyConfigured()
        public
    {
        priceRouter.addApprovedAdaptor(address(chainlinkAdaptor));

        vm.expectRevert("PriceRouter: adaptor already approved");
        priceRouter.addApprovedAdaptor(address(chainlinkAdaptor));
    }

    function test_addApprovedAdaptor_success() public {
        assertFalse(priceRouter.isApprovedAdaptor(address(chainlinkAdaptor)));

        priceRouter.addApprovedAdaptor(address(chainlinkAdaptor));

        assertTrue(priceRouter.isApprovedAdaptor(address(chainlinkAdaptor)));
    }
}
