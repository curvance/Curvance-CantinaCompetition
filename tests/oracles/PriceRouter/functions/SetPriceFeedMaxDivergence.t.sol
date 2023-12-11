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
        priceRouter.setCautionDivergenceFlag(10200);
    }

    function test_setCautionDivergenceFlag_fail_whenDivergenceIsTooSmall()
        public
    {
        vm.expectRevert(PriceRouter.PriceRouter__InvalidParameter.selector);
        priceRouter.setCautionDivergenceFlag(10199);
    }

    function test_setCautionDivergenceFlag_success() public {
        assertEq(priceRouter.cautionDivergenceFlag(), 10500);

        priceRouter.setCautionDivergenceFlag(10200);

        assertEq(priceRouter.cautionDivergenceFlag(), 10200);
    }

    function test_setBadSourceDivergenceFlag_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.prank(address(1));

        vm.expectRevert(PriceRouter.PriceRouter__Unauthorized.selector);
        priceRouter.setBadSourceDivergenceFlag(10200);
    }

    function test_setBadSourceDivergenceFlag_fail_whenDivergenceIsTooSmall()
        public
    {
        vm.expectRevert(PriceRouter.PriceRouter__InvalidParameter.selector);
        priceRouter.setBadSourceDivergenceFlag(10199);
    }

    function test_setBadSourceDivergenceFlag_success() public {
        assertEq(priceRouter.badSourceDivergenceFlag(), 11000);

        priceRouter.setBadSourceDivergenceFlag(10200);

        assertEq(priceRouter.badSourceDivergenceFlag(), 10200);
    }
}
