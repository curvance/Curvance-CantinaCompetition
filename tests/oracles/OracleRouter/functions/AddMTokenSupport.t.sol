// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseOracleRouter } from "../TestBaseOracleRouter.sol";
import { OracleRouter } from "contracts/oracles/OracleRouter.sol";

contract AddMTokenSupportTest is TestBaseOracleRouter {
    function test_addMTokenSupport_fail_whenCallerIsNotAuthorized() public {
        vm.prank(address(1));

        vm.expectRevert(OracleRouter.OracleRouter__Unauthorized.selector);
        oracleRouter.addMTokenSupport(address(mUSDC));
    }

    function test_addMTokenSupport_fail_whenMTokenIsAlreadyConfigured()
        public
    {
        oracleRouter.addMTokenSupport(address(mUSDC));

        vm.expectRevert(OracleRouter.OracleRouter__InvalidParameter.selector);
        oracleRouter.addMTokenSupport(address(mUSDC));
    }

    function test_addMTokenSupport_fail_whenMTokenIsInvalid() public {
        vm.expectRevert();
        oracleRouter.addMTokenSupport(address(1));
    }

    function test_addMTokenSupport_success() public {
        (bool isMToken, address underlying) = oracleRouter.mTokenAssets(
            address(mUSDC)
        );

        assertFalse(isMToken);
        assertEq(underlying, address(0));

        oracleRouter.addMTokenSupport(address(mUSDC));

        (isMToken, underlying) = oracleRouter.mTokenAssets(address(mUSDC));

        assertTrue(isMToken);
        assertEq(underlying, _USDC_ADDRESS);

        _addSinglePriceFeed();

        assertTrue(oracleRouter.isSupportedAsset(_USDC_ADDRESS));
    }
}
