// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { CentralRegistry } from "contracts/architecture/CentralRegistry.sol";

contract registerWormholeChainIDsTest is TestBaseMarket {
    uint256[] public chainIDs;
    uint16[] public wormholeChainIDs;

    function setUp() public override {
        super.setUp();

        chainIDs.push(1);
        wormholeChainIDs.push(2);
        chainIDs.push(42161);
        wormholeChainIDs.push(23);
        chainIDs.push(43114);
        wormholeChainIDs.push(6);
    }

    function test_registerWormholeChainIDs_fail_whenUnauthorized() public {
        vm.prank(address(0));

        vm.expectRevert(
            CentralRegistry.CentralRegistry__Unauthorized.selector
        );
        centralRegistry.registerWormholeChainIDs(chainIDs, wormholeChainIDs);
    }

    function test_registerWormholeChainIDs_success() public {
        centralRegistry.registerWormholeChainIDs(chainIDs, wormholeChainIDs);

        for (uint256 i = 0; i < chainIDs.length; i++) {
            assertEq(
                centralRegistry.wormholeChainId(chainIDs[i]),
                wormholeChainIDs[i]
            );
        }
    }
}
