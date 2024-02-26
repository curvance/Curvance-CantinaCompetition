// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { CentralRegistry } from "contracts/architecture/CentralRegistry.sol";

contract SetCVETest is TestBaseMarket {
    event CoreContractSet(string indexed contractType, address newAddress);

    address public newCVE = makeAddr("CVE");

    function test_setCVE_fail_whenUnauthorized() public {
        vm.prank(address(0));

        vm.expectRevert(
            CentralRegistry.CentralRegistry__Unauthorized.selector
        );
        centralRegistry.setCVE(newCVE);
    }

    function test_setCVE_success() public {
        assertEq(centralRegistry.cve(), address(cve));

        vm.expectEmit(true, true, true, true);
        emit CoreContractSet("CVE", newCVE);

        centralRegistry.setCVE(newCVE);

        assertEq(centralRegistry.cve(), newCVE);
    }
}
