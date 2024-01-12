// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { CVE } from "contracts/token/CVE.sol";

contract setBuilderAddressTest is TestBaseMarket {
    function test_setBuilderAddress_fail_whenUnauthorized() public {
        vm.startPrank(address(0));
        vm.expectRevert(CVE.CVE__Unauthorized.selector);
        cve.setBuilderAddress(user1);
        vm.stopPrank();
    }

    function test_setBuilderAddress_fail_whenParametersAreInvalid() public {
        address builderAddress = cve.builderAddress();
        vm.startPrank(builderAddress);
        vm.expectRevert(CVE.CVE__ParametersAreInvalid.selector);
        cve.setBuilderAddress(address(0));
        vm.stopPrank();
    }

    function test_setBuilderAddress_success() public {
        address builderAddress = cve.builderAddress();
        vm.prank(builderAddress);
        cve.setBuilderAddress(address(1));

        assertEq(cve.builderAddress(), address(1));
    }
}
