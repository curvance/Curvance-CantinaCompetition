// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBasePriceRouter } from "../TestBasePriceRouter.sol";

contract AddMTokenSupportTest is TestBasePriceRouter {
    function test_addMTokenSupport_fail_whenCallerIsNotAuthorized() public {
        vm.prank(address(1));

        vm.expectRevert("centralRegistry: UNAUTHORIZED");
        priceRouter.addMTokenSupport(address(mUSDC));
    }

    function test_addMTokenSupport_fail_whenMTokenIsAlreadyConfigured()
        public
    {
        priceRouter.addMTokenSupport(address(mUSDC));

        vm.expectRevert("PriceRouter: MToken already configured");
        priceRouter.addMTokenSupport(address(mUSDC));
    }

    function test_addMTokenSupport_fail_whenMTokenIsInvalid() public {
        vm.expectRevert("PriceRouter: MToken is invalid");
        priceRouter.addMTokenSupport(address(1));
    }

    function test_addMTokenSupport_success() public {
        (bool isMToken, address underlying) = priceRouter.mTokenAssets(
            address(mUSDC)
        );

        assertFalse(isMToken);
        assertEq(underlying, address(0));

        priceRouter.addMTokenSupport(address(mUSDC));

        (isMToken, underlying) = priceRouter.mTokenAssets(address(mUSDC));

        assertTrue(isMToken);
        assertEq(underlying, _USDC_ADDRESS);

        _addSinglePriceFeed();

        assertTrue(priceRouter.isSupportedAsset(_USDC_ADDRESS));
    }
}