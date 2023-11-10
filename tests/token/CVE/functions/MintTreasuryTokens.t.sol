// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { CVE } from "contracts/token/CVE.sol";

contract MintTreasuryTokensTest is TestBaseMarket {
    function test_mintTreasuryTokens_fail_whenUnauthorized() public {
        vm.prank(address(0));
        vm.expectRevert("centralRegistry: UNAUTHORIZED");
        cve.mintTreasuryTokens(1000);
    }

    function test_mintTreasuryTokens_fail_whenInsufficientCVEAllocation()
        public
    {
        uint256 invalidAmount = cve.daoTreasuryAllocation() + 1;
        vm.expectRevert(CVE.CVE__InsufficientCVEAllocation.selector);
        cve.mintTreasuryTokens(invalidAmount);
    }

    function test_mintTreasuryTokens_success() public {
        uint256 validAmount = cve.daoTreasuryAllocation();
        uint256 prevBalance = cve.balanceOf(address(this));
        cve.mintTreasuryTokens(validAmount);

        assertEq(cve.daoTreasuryMinted(), validAmount);
        assertEq(cve.balanceOf(address(this)), prevBalance + validAmount);
    }
}
