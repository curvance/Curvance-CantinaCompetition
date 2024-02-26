// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { CentralRegistry } from "contracts/architecture/CentralRegistry.sol";

contract SetVeCVETest is TestBaseMarket {
    event CoreContractSet(string indexed contractType, address newAddress);

    address public newVeCVE = makeAddr("VeCVE");

    function test_setVeCVE_fail_whenUnauthorized() public {
        vm.prank(address(0));

        vm.expectRevert(
            CentralRegistry.CentralRegistry__Unauthorized.selector
        );
        centralRegistry.setVeCVE(newVeCVE);
    }

    function test_setVeCVE_success() public {
        assertEq(centralRegistry.veCVE(), address(veCVE));

        vm.expectEmit(true, true, true, true);
        emit CoreContractSet("VeCVE", newVeCVE);

        centralRegistry.setVeCVE(newVeCVE);

        assertEq(centralRegistry.veCVE(), newVeCVE);
    }
}
