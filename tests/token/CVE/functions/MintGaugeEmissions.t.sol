// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { CVE } from "contracts/token/CVE.sol";

contract MintGaugeEmissionsTest is TestBaseMarket {
    function test_mintGaugeEmissions_fail_whenUnauthorized() public {
        vm.expectRevert(CVE.CVE__Unauthorized.selector);
        cve.mintGaugeEmissions(address(gaugePool), 1000);
    }

    function test_mintGaugeEmissions_success() public {
        assertEq(cve.balanceOf(address(gaugePool)), 0);
        vm.prank(centralRegistry.protocolMessagingHub());
        cve.mintGaugeEmissions(address(gaugePool), 1000);
        assertEq(cve.balanceOf(address(gaugePool)), 1000);
    }
}
