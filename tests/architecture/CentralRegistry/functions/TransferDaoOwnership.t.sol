// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { CentralRegistry } from "contracts/architecture/CentralRegistry.sol";

contract TransferDaoOwnershipTest is TestBaseMarket {
    address newDaoAddress = address(1000);

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    function test_transferDaoOwnership_fail_whenUnauthorized() public {
        vm.startPrank(address(0));
        vm.expectRevert(CentralRegistry.CentralRegistry__Unauthorized.selector);
        centralRegistry.transferDaoOwnership(newDaoAddress);
        vm.stopPrank();
    }

    function test_transferDaoOwnership_success() public {
        assertTrue(centralRegistry.hasDaoPermissions(address(this)));
        vm.expectEmit(true, true, true, true);
        emit OwnershipTransferred(address(this), newDaoAddress);
        centralRegistry.transferDaoOwnership(newDaoAddress);
        assertEq(centralRegistry.daoAddress(), newDaoAddress);
        assertTrue(centralRegistry.hasDaoPermissions(newDaoAddress));
        assertFalse(centralRegistry.hasDaoPermissions(address(this)));
    }
}
