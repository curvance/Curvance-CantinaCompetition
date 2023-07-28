// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBasePriceRouter } from "../TestBasePriceRouter.sol";

contract RemoveMTokenSupportTest is TestBasePriceRouter {
    function test_removeMTokenSupport_fail_whenCallerIsNotAuthorized() public {
        vm.prank(address(1));

        vm.expectRevert("centralRegistry: UNAUTHORIZED");
        priceRouter.removeMTokenSupport(address(cUSDC));
    }

    function test_removeMTokenSupport_fail_whenMTokenIsNotConfigured() public {
        vm.expectRevert("PriceRouter: MToken is not configured");
        priceRouter.removeMTokenSupport(address(cUSDC));
    }

    function test_removeMTokenSupport_success() public {
        priceRouter.addMTokenSupport(address(cUSDC));

        (bool isMToken, address underlying) = priceRouter.MTokenAssets(
            address(cUSDC)
        );

        assertTrue(isMToken);
        assertEq(underlying, _USDC_ADDRESS);

        priceRouter.removeMTokenSupport(address(cUSDC));

        (isMToken, underlying) = priceRouter.MTokenAssets(address(cUSDC));

        assertFalse(isMToken);
        assertEq(underlying, address(0));
    }
}
