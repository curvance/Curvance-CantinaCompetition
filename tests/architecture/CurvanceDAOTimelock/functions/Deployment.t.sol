// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseTimelock } from "../TestBaseTimelock.sol";
import { Timelock } from "contracts/architecture/CurvanceDAOTimelock.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract TimelockDeploymentTest is TestBaseTimelock {
    function test_timelockDeployment_fail_whenCentralRegistryIsInvalid()
        public
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                Timelock.Timelock__InvalidCentralRegistry.selector,
                address(0)
            )
        );
        new Timelock(ICentralRegistry(address(0)));
    }

    function test_timelockDeployment_success() public {
        Timelock timelock = new Timelock(
            ICentralRegistry(address(centralRegistry))
        );

        assertEq(
            address(timelock.centralRegistry()),
            address(centralRegistry)
        );
        assertTrue(
            timelock.hasRole(
                timelock.PROPOSER_ROLE(),
                centralRegistry.daoAddress()
            )
        );
        assertTrue(
            timelock.hasRole(
                timelock.EXECUTOR_ROLE(),
                centralRegistry.daoAddress()
            )
        );
    }
}
