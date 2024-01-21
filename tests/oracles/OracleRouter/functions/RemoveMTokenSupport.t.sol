// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseOracleRouter } from "../TestBaseOracleRouter.sol";
import { OracleRouter } from "contracts/oracles/OracleRouter.sol";

contract RemoveMTokenSupportTest is TestBaseOracleRouter {
    function test_removeMTokenSupport_fail_whenCallerIsNotAuthorized() public {
        vm.prank(address(1));

        vm.expectRevert(OracleRouter.OracleRouter__Unauthorized.selector);
        oracleRouter.removeMTokenSupport(address(mUSDC));
    }

    function test_removeMTokenSupport_fail_whenMTokenIsNotConfigured() public {
        vm.expectRevert(OracleRouter.OracleRouter__InvalidParameter.selector);
        oracleRouter.removeMTokenSupport(address(mUSDC));
    }

    function test_removeMTokenSupport_success() public {
        oracleRouter.addMTokenSupport(address(mUSDC));

        (bool isMToken, address underlying) = oracleRouter.mTokenAssets(
            address(mUSDC)
        );

        assertTrue(isMToken);
        assertEq(underlying, _USDC_ADDRESS);

        oracleRouter.removeMTokenSupport(address(mUSDC));

        (isMToken, underlying) = oracleRouter.mTokenAssets(address(mUSDC));

        assertFalse(isMToken);
        assertEq(underlying, address(0));
    }
}
