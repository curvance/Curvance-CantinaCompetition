// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { CentralRegistry } from "contracts/architecture/CentralRegistry.sol";

contract DisableDelegableTest is TestBaseMarket {
    event DelegableStatusSet(address indexed user, bool delegable);

    function test_disableDelegable_success() public {
        vm.startPrank(user1);

        assertFalse(centralRegistry.delegatingDisabled(user1));

        vm.expectEmit(true, true, true, true);
        emit DelegableStatusSet(user1, true);

        centralRegistry.disableDelegable(true);

        assertTrue(centralRegistry.delegatingDisabled(user1));

        vm.expectEmit(true, true, true, true);
        emit DelegableStatusSet(user1, false);

        centralRegistry.disableDelegable(false);

        assertFalse(centralRegistry.delegatingDisabled(user1));

        vm.stopPrank();
    }
}
