// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseTimelock } from "../TestBaseTimelock.sol";
import { Timelock } from "contracts/architecture/CurvanceDAOTimelock.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract UpdateDaoAddressTest is TestBaseTimelock {
    function test_updateDaoAddress_success() public {
        Timelock timelock = new Timelock(
            ICentralRegistry(address(centralRegistry))
        );

        address daoAddress = centralRegistry.daoAddress();

        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), daoAddress));
        assertTrue(timelock.hasRole(timelock.EXECUTOR_ROLE(), daoAddress));

        timelock.updateDaoAddress();

        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), daoAddress));
        assertTrue(timelock.hasRole(timelock.EXECUTOR_ROLE(), daoAddress));

        vm.prank(daoAddress);
        centralRegistry.transferDaoOwnership(address(1));

        timelock.updateDaoAddress();

        assertFalse(timelock.hasRole(timelock.PROPOSER_ROLE(), daoAddress));
        assertFalse(timelock.hasRole(timelock.EXECUTOR_ROLE(), daoAddress));
        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), address(1)));
        assertTrue(timelock.hasRole(timelock.EXECUTOR_ROLE(), address(1)));
    }
}
