// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseChildCVE } from "../TestBaseChildCVE.sol";
import { CVE } from "contracts/token/ChildCVE.sol";

contract MintGaugeEmissionsTest is TestBaseChildCVE {
    function test_mintGaugeEmissions_fail_whenUnauthorized() public {
        vm.expectRevert(CVE.CVE__Unauthorized.selector);
        childCVE.mintGaugeEmissions(address(gaugePool), 1000);
    }

    function test_mintGaugeEmissions_success() public {
        assertEq(childCVE.balanceOf(address(gaugePool)), 0);
        vm.prank(centralRegistry.protocolMessagingHub());
        childCVE.mintGaugeEmissions(address(gaugePool), 1000);
        assertEq(childCVE.balanceOf(address(gaugePool)), 1000);
    }
}
