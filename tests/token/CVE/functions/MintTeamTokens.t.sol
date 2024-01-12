// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { CVE } from "contracts/token/CVE.sol";

contract MintBuilderTest is TestBaseMarket {
    function test_mintBuilder_fail_whenUnauthorized() public {
        vm.prank(address(0));
        vm.expectRevert(CVE.CVE__Unauthorized.selector);
        cve.mintBuilder();
    }

    function test_mintBuilder_fail_whenCVEParametersAreInvalid() public {
        address builderAddress = cve.builderAddress();
        vm.prank(builderAddress);
        vm.expectRevert(CVE.CVE__ParametersAreInvalid.selector);
        cve.mintBuilder();
    }

    function test_mintBuilder_success() public {
        assertEq(cve.builderAllocationMinted(), 0);

        skip(62 days);
        address builderAddress = cve.builderAddress();
        uint256 prevBalance = cve.balanceOf(builderAddress);
        vm.prank(builderAddress);
        cve.mintBuilder();

        // 2 months worth of team allocation
        uint256 expectedAmount = 2 * cve.builderAllocationPerMonth();
        assertEq(expectedAmount, cve.builderAllocationMinted());
        assertEq(cve.balanceOf(builderAddress), prevBalance + expectedAmount);

        skip(31 days);
        vm.prank(builderAddress);
        cve.mintBuilder();

        // 3 months worth of team allocation
        expectedAmount = cve.builderAllocationPerMonth() * 3;
        assertEq(expectedAmount, cve.builderAllocationMinted());
        assertEq(cve.balanceOf(builderAddress), prevBalance + expectedAmount);

        // 4 years
        skip(1460 days);
        vm.prank(builderAddress);
        cve.mintBuilder();

        expectedAmount = cve.teamAllocation();
        assertEq(expectedAmount, cve.builderAllocationMinted());
        assertEq(cve.balanceOf(builderAddress), prevBalance + expectedAmount);
    }
}
