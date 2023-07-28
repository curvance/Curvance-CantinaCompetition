// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBasePriceRouter } from "../TestBasePriceRouter.sol";

contract AddMTokenSupportTest is TestBasePriceRouter {
    function test_addMTokenSupport_fail_whenCallerIsNotAuthorized() public {
        vm.prank(address(1));

        vm.expectRevert("centralRegistry: UNAUTHORIZED");
        priceRouter.addMTokenSupport(address(cUSDC));
    }

    function test_addMTokenSupport_fail_whenMTokenIsAlreadyConfigured()
        public
    {
        priceRouter.addMTokenSupport(address(cUSDC));

        vm.expectRevert("PriceRouter: MToken already configured");
        priceRouter.addMTokenSupport(address(cUSDC));
    }

    function test_addMTokenSupport_fail_whenMTokenIsInvalid() public {
        vm.expectRevert("PriceRouter: MToken is invalid");
        priceRouter.addMTokenSupport(address(1));
    }

    function test_addMTokenSupport_success() public {
        (bool isMToken, address underlying) = priceRouter.MTokenAssets(
            address(cUSDC)
        );

        assertFalse(isMToken);
        assertEq(underlying, address(0));

        priceRouter.addMTokenSupport(address(cUSDC));

        (isMToken, underlying) = priceRouter.MTokenAssets(address(cUSDC));

        assertTrue(isMToken);
        assertEq(underlying, _USDC_ADDRESS);

        _addSinglePriceFeed();

        assertTrue(priceRouter.isSupportedAsset(_USDC_ADDRESS));
    }
}
