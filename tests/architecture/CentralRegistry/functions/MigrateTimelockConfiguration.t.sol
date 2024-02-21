// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { CentralRegistry } from "contracts/architecture/CentralRegistry.sol";

contract MigrateTimelockConfigurationTest is TestBaseMarket {
    address newTimelock = address(1000);

    event NewTimelockConfiguration(
        address indexed previousTimelock,
        address indexed newTimelock
    );

    function test_migrateTimelockConfiguration_fail_whenUnauthorized() public {
        vm.prank(address(0));

        vm.expectRevert(
            CentralRegistry.CentralRegistry__Unauthorized.selector
        );
        centralRegistry.migrateTimelockConfiguration(newTimelock);
    }

    function test_migrateTimelockConfiguration_success() public {
        assertTrue(centralRegistry.hasDaoPermissions(address(this)));
        assertTrue(centralRegistry.hasElevatedPermissions(address(this)));
        vm.expectEmit(true, true, true, true);
        emit NewTimelockConfiguration(address(this), newTimelock);
        centralRegistry.migrateTimelockConfiguration(newTimelock);
        assertTrue(centralRegistry.hasDaoPermissions(newTimelock));
        assertFalse(centralRegistry.hasDaoPermissions(address(this)));
        assertTrue(centralRegistry.hasElevatedPermissions(newTimelock));
        assertFalse(centralRegistry.hasElevatedPermissions(address(this)));
    }
}
