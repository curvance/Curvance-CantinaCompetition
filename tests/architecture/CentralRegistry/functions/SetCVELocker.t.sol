// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { CentralRegistry } from "contracts/architecture/CentralRegistry.sol";

contract SetCVELockerTest is TestBaseMarket {
    event CoreContractSet(string indexed contractType, address newAddress);

    address public newCVELocker = makeAddr("CVE Locker");

    function test_setCVELocker_fail_whenUnauthorized() public {
        vm.prank(address(0));

        vm.expectRevert(
            CentralRegistry.CentralRegistry__Unauthorized.selector
        );
        centralRegistry.setCVELocker(newCVELocker);
    }

    function test_setCVELocker_success() public {
        assertEq(centralRegistry.cveLocker(), address(cveLocker));

        vm.expectEmit(true, true, true, true);
        emit CoreContractSet("CVE Locker", newCVELocker);

        centralRegistry.setCVELocker(newCVELocker);

        assertEq(centralRegistry.cveLocker(), newCVELocker);
    }
}
