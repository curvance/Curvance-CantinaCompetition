// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseChildCVE } from "../TestBaseChildCVE.sol";
import { ERC20 } from "contracts/libraries/external/ERC20.sol";

contract BridgeTest is TestBaseChildCVE {
    uint256[] public chainIDs;
    uint16[] public wormholeChainIDs;

    function setUp() public override {
        super.setUp();

        centralRegistry.setCVE(address(childCVE));
        _deployProtocolMessagingHub();

        chainIDs.push(1);
        wormholeChainIDs.push(2);
        chainIDs.push(137);
        wormholeChainIDs.push(5);

        centralRegistry.registerWormholeChainIDs(chainIDs, wormholeChainIDs);

        vm.prank(centralRegistry.protocolMessagingHub());
        childCVE.mintGaugeEmissions(user1, _ONE);
    }

    function test_bridge_fail_whenUserHasNoEnoughCVE() public {
        vm.prank(user1);

        vm.expectRevert(ERC20.InsufficientBalance.selector);
        childCVE.bridge(137, user1, _ONE + 1);
    }

    function test_bridge_fail_whenDestinationChainIsNotRegistered() public {
        vm.prank(user1);

        vm.expectRevert("target not registered");
        childCVE.bridge(138, user1, _ONE);
    }

    function test_bridge_fail_whenRecipientIsZeroAddress() public {
        vm.prank(user1);

        vm.expectRevert("targetRecipient cannot be bytes32(0)");
        childCVE.bridge(137, address(0), _ONE);
    }

    function test_bridge_success() public {
        vm.prank(user1);

        childCVE.bridge(137, user1, _ONE);

        assertEq(childCVE.balanceOf(user1), 0);
        assertEq(childCVE.balanceOf(_TOKEN_BRIDGE), _ONE);
    }
}
