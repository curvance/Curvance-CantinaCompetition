// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { CVE } from "contracts/token/CVE.sol";

contract MintLockBoostTest is TestBaseMarket {
    function test_mintLockBoost_fail_whenUnauthorized() public {
        vm.expectRevert(CVE.CVE__Unauthorized.selector);
        cve.mintLockBoost(1000);
    }

    function test_mintLockBoost_success() public {
        centralRegistry.addGaugeController(user1);
        assertTrue(centralRegistry.isGaugeController(user1));

        assertEq(cve.balanceOf(user1), 0);
        vm.prank(user1);
        cve.mintLockBoost(1000);
        assertEq(cve.balanceOf(user1), 1000);
    }
}
