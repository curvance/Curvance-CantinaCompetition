// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBasePriceRouterV2 } from "../TestBasePriceRouterV2.sol";

contract AddCTokenSupportTest is TestBasePriceRouterV2 {
    function test_addCTokenSupport_fail_whenCallerIsNotAuthorized() public {
        vm.prank(address(1));

        vm.expectRevert("centralRegistry: UNAUTHORIZED");
        priceRouter.addCTokenSupport(address(cUSDC));
    }

    function test_addCTokenSupport_fail_whenCTokenIsAlreadyConfigured()
        public
    {
        priceRouter.addCTokenSupport(address(cUSDC));

        vm.expectRevert("PriceRouter: CToken already configured");
        priceRouter.addCTokenSupport(address(cUSDC));
    }

    function test_addCTokenSupport_fail_whenCTokenIsInvalid() public {
        vm.expectRevert("PriceRouter: CToken is invalid");
        priceRouter.addCTokenSupport(address(1));
    }

    function test_addCTokenSupport_success() public {
        (bool isCToken, address underlying) = priceRouter.cTokenAssets(
            address(cUSDC)
        );

        assertFalse(isCToken);
        assertEq(underlying, address(0));

        priceRouter.addCTokenSupport(address(cUSDC));

        (isCToken, underlying) = priceRouter.cTokenAssets(address(cUSDC));

        assertTrue(isCToken);
        assertEq(underlying, _USDC_ADDRESS);

        _addSinglePriceFeed();

        assertTrue(priceRouter.isSupportedAsset(_USDC_ADDRESS));
    }
}
