// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { CVE } from "contracts/token/CVE.sol";

contract SetTeamAddressTest is TestBaseMarket {
    function test_setTeamAddress_fail_whenUnauthorized() public {
        vm.startPrank(address(0));
        vm.expectRevert(CVE.CVE__Unauthorized.selector);
        cve.setTeamAddress(user1);
        vm.stopPrank();
    }

    function test_setTeamAddress_fail_whenParametersAreInvalid() public {
        address teamAddress = cve.teamAddress();
        vm.startPrank(teamAddress);
        vm.expectRevert(CVE.CVE__ParametersAreInvalid.selector);
        cve.setTeamAddress(address(0));
        vm.stopPrank();
    }

    function test_setTeamAddress_success() public {
        address teamAddress = cve.teamAddress();
        vm.prank(teamAddress);
        cve.setTeamAddress(address(1));

        assertEq(cve.teamAddress(), address(1));
    }
}
