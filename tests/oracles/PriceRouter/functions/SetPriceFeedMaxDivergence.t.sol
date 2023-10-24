// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBasePriceRouter } from "../TestBasePriceRouter.sol";
import { PriceRouter } from "contracts/oracles/PriceRouter.sol";

contract SetPriceFeedMaxDivergenceTest is TestBasePriceRouter {
    function test_setPriceFeedMaxDivergence_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.prank(address(1));

        vm.expectRevert(PriceRouter.PriceRouter__Unauthorized.selector);
        priceRouter.setPriceFeedMaxDivergence(10200);
    }

    function test_setPriceFeedMaxDivergence_fail_whenDivergenceIsTooSmall()
        public
    {
        vm.expectRevert(PriceRouter.PriceRouter__InvalidParameter.selector);
        priceRouter.setPriceFeedMaxDivergence(10199);
    }

    function test_setPriceFeedMaxDivergence_success() public {
        assertEq(priceRouter.MAXIMUM_DIVERGENCE(), 11000);

        priceRouter.setPriceFeedMaxDivergence(10200);

        assertEq(priceRouter.MAXIMUM_DIVERGENCE(), 10200);
    }
}
