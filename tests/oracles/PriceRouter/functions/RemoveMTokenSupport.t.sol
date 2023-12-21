// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBasePriceRouter } from "../TestBasePriceRouter.sol";
import { PriceRouter } from "contracts/oracles/PriceRouter.sol";

contract RemoveMTokenSupportTest is TestBasePriceRouter {
    function test_removeMTokenSupport_fail_whenCallerIsNotAuthorized() public {
        vm.prank(address(1));

        vm.expectRevert(PriceRouter.PriceRouter__Unauthorized.selector);
        priceRouter.removeMTokenSupport(address(mUSDC));
    }

    function test_removeMTokenSupport_fail_whenMTokenIsNotConfigured() public {
        vm.expectRevert(PriceRouter.PriceRouter__InvalidParameter.selector);
        priceRouter.removeMTokenSupport(address(mUSDC));
    }

    function test_removeMTokenSupport_success() public {
        priceRouter.addMTokenSupport(address(mUSDC));

        (bool isMToken, address underlying) = priceRouter.mTokenAssets(
            address(mUSDC)
        );

        assertTrue(isMToken);
        assertEq(underlying, _USDC_ADDRESS);

        priceRouter.removeMTokenSupport(address(mUSDC));

        (isMToken, underlying) = priceRouter.mTokenAssets(address(mUSDC));

        assertFalse(isMToken);
        assertEq(underlying, address(0));
    }
}
