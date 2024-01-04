// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBasePriceRouter } from "../TestBasePriceRouter.sol";
import { PriceRouter } from "contracts/oracles/PriceRouter.sol";

contract SetPriceFeedMaxDivergenceTest is TestBasePriceRouter {
    function test_setCautionDivergenceFlag_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.prank(address(1));

        vm.expectRevert(PriceRouter.PriceRouter__Unauthorized.selector);
        priceRouter.setDivergenceFlags(10200, 10200);
    }

    function test_setCautionDivergenceFlag_fail_whenDivergenceIsTooSmall()
        public
    {
        vm.expectRevert(PriceRouter.PriceRouter__InvalidParameter.selector);
        priceRouter.setDivergenceFlags(10199, 10200);
    }

    function test_setCautionDivergenceFlag_fail_whenDivergenceIsTooLarge()
        public
    {
        vm.expectRevert(PriceRouter.PriceRouter__InvalidParameter.selector);
        priceRouter.setDivergenceFlags(12001, 10200);
    }

    function test_setCautionDivergenceFlag_success() public {
        assertEq(priceRouter.cautionDivergenceFlag(), 10500);

        priceRouter.setDivergenceFlags(10200, 11000);

        assertEq(priceRouter.cautionDivergenceFlag(), 10200);
    }

    function test_setBadSourceDivergenceFlag_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.prank(address(1));

        vm.expectRevert(PriceRouter.PriceRouter__Unauthorized.selector);
        priceRouter.setDivergenceFlags(10200, 10200);
    }

    function test_setBadSourceDivergenceFlag_fail_whenDivergenceIsTooSmall()
        public
    {
        vm.expectRevert(PriceRouter.PriceRouter__InvalidParameter.selector);
        priceRouter.setDivergenceFlags(10200, 10199);
    }

    function test_setBadSourceDivergenceFlag_fail_whenDivergenceIsTooLarge()
        public
    {
        vm.expectRevert(PriceRouter.PriceRouter__InvalidParameter.selector);
        priceRouter.setDivergenceFlags(10200, 12001);
    }

    function test_setBadSourceDivergenceFlag_success() public {
        assertEq(priceRouter.badSourceDivergenceFlag(), 11000);

        priceRouter.setDivergenceFlags(11000, 10200);

        assertEq(priceRouter.badSourceDivergenceFlag(), 10200);
    }

    function test_setDivergenceFlags_fail_whenCautionEqualToBadSource()
        public
    {
        vm.expectRevert(PriceRouter.PriceRouter__InvalidParameter.selector);
        priceRouter.setDivergenceFlags(10200, 10200);
    }

    function test_setDivergenceFlags_fail_whenCautionLargerThanBadSource()
        public
    {
        vm.expectRevert(PriceRouter.PriceRouter__InvalidParameter.selector);
        priceRouter.setDivergenceFlags(10500, 10200);
    }

}
