// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseChildCVE } from "../TestBaseChildCVE.sol";
import { CVE } from "contracts/token/ChildCVE.sol";

contract MintLockBoostTest is TestBaseChildCVE {
    function test_mintLockBoost_fail_whenUnauthorized() public {
        vm.prank(address(0));
        vm.expectRevert(CVE.CVE__Unauthorized.selector);
        childCVE.mintLockBoost(1000);
    }

    function test_mintLockBoost_success() public {
        centralRegistry.addGaugeController(user1);
        assertTrue(centralRegistry.isGaugeController(user1));

        assertEq(childCVE.balanceOf(user1), 0);
        vm.prank(user1);
        childCVE.mintLockBoost(1000);
        assertEq(childCVE.balanceOf(user1), 1000);
    }
}
