// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBasePriceRouterV2 } from "../TestBasePriceRouterV2.sol";

contract RemoveCTokenSupportTest is TestBasePriceRouterV2 {
    function test_removeCTokenSupport_fail_whenCallerIsNotAuthorized() public {
        vm.prank(address(1));

        vm.expectRevert("centralRegistry: UNAUTHORIZED");
        priceRouter.removeCTokenSupport(address(cUSDC));
    }

    function test_removeCTokenSupport_fail_whenCTokenIsNotConfigured() public {
        vm.expectRevert("priceRouter: CToken is not configured");
        priceRouter.removeCTokenSupport(address(cUSDC));
    }

    function test_removeCTokenSupport_success() public {
        priceRouter.addCTokenSupport(address(cUSDC));

        (bool isCToken, address underlying) = priceRouter.cTokenAssets(
            address(cUSDC)
        );

        assertTrue(isCToken);
        assertEq(underlying, _USDC_ADDRESS);

        priceRouter.removeCTokenSupport(address(cUSDC));

        (isCToken, underlying) = priceRouter.cTokenAssets(address(cUSDC));

        assertFalse(isCToken);
        assertEq(underlying, address(0));
    }
}
