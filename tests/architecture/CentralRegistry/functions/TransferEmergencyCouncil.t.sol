// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { CentralRegistry } from "contracts/architecture/CentralRegistry.sol";

contract TransferEmergencyCouncilTest is TestBaseMarket {
    address newEmergencyCouncil = address(1000);

    event EmergencyCouncilTransferred(
        address indexed previousEmergencyCouncil,
        address indexed newEmergencyCouncil
    );

    function test_transferEmergencyCouncil_fail_whenUnauthorized() public {
        vm.startPrank(address(0));
        vm.expectRevert(CentralRegistry.CentralRegistry_Unauthorized.selector);
        centralRegistry.transferEmergencyCouncil(newEmergencyCouncil);
        vm.stopPrank();
    }

    function test_transferEmergencyCouncil_success() public {
        assertTrue(centralRegistry.hasDaoPermissions(address(this)));
        assertTrue(centralRegistry.hasElevatedPermissions(address(this)));
        vm.expectEmit(true, true, true, true);
        emit EmergencyCouncilTransferred(address(this), newEmergencyCouncil);
        centralRegistry.transferEmergencyCouncil(newEmergencyCouncil);
        assertTrue(centralRegistry.hasDaoPermissions(newEmergencyCouncil));
        assertFalse(centralRegistry.hasDaoPermissions(address(this)));
        assertTrue(
            centralRegistry.hasElevatedPermissions(newEmergencyCouncil)
        );
        assertFalse(centralRegistry.hasElevatedPermissions(address(this)));
    }
}
