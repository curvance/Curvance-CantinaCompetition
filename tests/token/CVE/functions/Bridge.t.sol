// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { ERC20 } from "contracts/libraries/external/ERC20.sol";

contract BridgeTest is TestBaseMarket {
    uint256[] public chainIDs;
    uint16[] public wormholeChainIDs;

    function setUp() public override {
        super.setUp();

        chainIDs.push(1);
        wormholeChainIDs.push(2);
        chainIDs.push(137);
        wormholeChainIDs.push(5);

        centralRegistry.registerWormholeChainIDs(chainIDs, wormholeChainIDs);

        deal(address(cve), user1, _ONE);
    }

    function test_bridge_fail_whenUserHasNoEnoughCVE() public {
        vm.prank(user1);

        vm.expectRevert(ERC20.InsufficientBalance.selector);
        cve.bridge(137, user1, _ONE + 1);
    }

    function test_bridge_fail_whenDestinationChainIsNotRegistered() public {
        vm.prank(user1);

        vm.expectRevert("target not registered");
        cve.bridge(138, user1, _ONE);
    }

    function test_bridge_fail_whenRecipientIsZeroAddress() public {
        vm.prank(user1);

        vm.expectRevert("targetRecipient cannot be bytes32(0)");
        cve.bridge(137, address(0), _ONE);
    }

    function test_bridge_success() public {
        vm.prank(user1);

        cve.bridge(137, user1, _ONE);

        assertEq(cve.balanceOf(user1), 0);
        assertEq(cve.balanceOf(_TOKEN_BRIDGE), _ONE);
    }
}
