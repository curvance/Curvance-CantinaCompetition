// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseProtocolMessagingHub } from "../TestBaseProtocolMessagingHub.sol";
import { ProtocolMessagingHub } from "contracts/architecture/ProtocolMessagingHub.sol";

contract registerWormholeChainIDsTest is TestBaseProtocolMessagingHub {
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
            ProtocolMessagingHub.ProtocolMessagingHub__Unauthorized.selector
        );
        protocolMessagingHub.registerWormholeChainIDs(
            chainIDs,
            wormholeChainIDs
        );
    }

    function test_registerWormholeChainIDs_success() public {
        protocolMessagingHub.registerWormholeChainIDs(
            chainIDs,
            wormholeChainIDs
        );

        for (uint256 i = 0; i < chainIDs.length; i++) {
            assertEq(
                protocolMessagingHub.wormholeChainId(chainIDs[i]),
                wormholeChainIDs[i]
            );
        }
    }
}
