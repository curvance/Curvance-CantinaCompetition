// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBasePriceRouter } from "../TestBasePriceRouter.sol";

contract SetPriceFeedMaxDivergenceTest is TestBasePriceRouter {
    function test_setPriceFeedMaxDivergence_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.prank(address(1));

        vm.expectRevert("centralRegistry: UNAUTHORIZED");
        priceRouter.setPriceFeedMaxDivergence(10200);
    }

    function test_setPriceFeedMaxDivergence_fail_whenDivergenceIsTooSmall()
        public
    {
        vm.expectRevert("PriceRouter: divergence check is too small");
        priceRouter.setPriceFeedMaxDivergence(10199);
    }

    function test_setPriceFeedMaxDivergence_success() public {
        assertEq(priceRouter.PRICEFEED_MAXIMUM_DIVERGENCE(), 11000);

        priceRouter.setPriceFeedMaxDivergence(10200);

        assertEq(priceRouter.PRICEFEED_MAXIMUM_DIVERGENCE(), 10200);
    }
}
