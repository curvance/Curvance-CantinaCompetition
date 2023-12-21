// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { CVE } from "contracts/token/CVE.sol";

contract MintCallOptionTokensTest is TestBaseMarket {
    function test_mintCallOptionTokens_fail_whenUnauthorized() public {
        vm.prank(address(0));
        vm.expectRevert(CVE.CVE__Unauthorized.selector);
        cve.mintCallOptionTokens(1000);
    }

    function test_mintCallOptionTokens_fail_whenInsufficientCVEAllocation()
        public
    {
        assertEq(cve.callOptionsMinted(), 0);
        uint256 invalidAmount = cve.callOptionAllocation() + 1;

        vm.expectRevert(CVE.CVE__InsufficientCVEAllocation.selector);
        cve.mintCallOptionTokens(invalidAmount);
    }

    function test_mintCallOptionTokens_success() public {
        assertEq(cve.callOptionsMinted(), 0);
        uint256 validAmount = cve.callOptionAllocation();
        uint256 prevBalance = cve.balanceOf(address(this));
        cve.mintCallOptionTokens(validAmount);

        assertEq(cve.callOptionsMinted(), validAmount);
        assertEq(cve.balanceOf(address(this)), prevBalance + validAmount);
    }
}
