// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { CVE } from "contracts/token/CVE.sol";

contract MintTeamTokensTest is TestBaseMarket {
    function test_mintTeamTokens_fail_whenUnauthorized() public {
        vm.prank(address(0));
        vm.expectRevert(CVE.CVE__Unauthorized.selector);
        cve.mintTeamTokens();
    }

    function test_mintTeamTokens_fail_whenCVEParametersAreInvalid() public {
        address teamAddress = cve.teamAddress();
        vm.prank(teamAddress);
        vm.expectRevert(CVE.CVE__ParametersAreInvalid.selector);
        cve.mintTeamTokens();
    }

    function test_mintTeamTokens_success() public {
        assertEq(cve.teamAllocationMinted(), 0);

        skip(62 days);
        address teamAddress = cve.teamAddress();
        uint256 prevBalance = cve.balanceOf(teamAddress);
        vm.prank(teamAddress);
        cve.mintTeamTokens();

        // 2 months worth of team allocation
        uint256 expectedAmount = 2 * cve.teamAllocationPerMonth();
        assertEq(expectedAmount, cve.teamAllocationMinted());
        assertEq(cve.balanceOf(teamAddress), prevBalance + expectedAmount);

        skip(31 days);
        vm.prank(teamAddress);
        cve.mintTeamTokens();

        // 3 months worth of team allocation
        expectedAmount = cve.teamAllocationPerMonth() * 3;
        assertEq(expectedAmount, cve.teamAllocationMinted());
        assertEq(cve.balanceOf(teamAddress), prevBalance + expectedAmount);

        // 4 years
        skip(1460 days);
        vm.prank(teamAddress);
        cve.mintTeamTokens();

        expectedAmount = cve.teamAllocation();
        assertEq(expectedAmount, cve.teamAllocationMinted());
        assertEq(cve.balanceOf(teamAddress), prevBalance + expectedAmount);
    }
}
