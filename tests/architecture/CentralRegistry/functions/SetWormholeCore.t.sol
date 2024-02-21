// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { CentralRegistry } from "contracts/architecture/CentralRegistry.sol";

contract SetWormholeCoreTest is TestBaseMarket {
    event WormholeCoreSet(address newAddress);

    address public newWormholeCore = makeAddr("Wormhole Core");

    function test_setWormholeCore_fail_whenUnauthorized() public {
        vm.prank(address(0));

        vm.expectRevert(
            CentralRegistry.CentralRegistry__Unauthorized.selector
        );
        centralRegistry.setWormholeCore(newWormholeCore);
    }

    function test_setWormholeCore_success() public {
        assertEq(address(centralRegistry.wormholeCore()), _WORMHOLE_CORE);

        vm.expectEmit(true, true, true, true);
        emit WormholeCoreSet(newWormholeCore);

        centralRegistry.setWormholeCore(newWormholeCore);

        assertEq(address(centralRegistry.wormholeCore()), newWormholeCore);
    }
}
