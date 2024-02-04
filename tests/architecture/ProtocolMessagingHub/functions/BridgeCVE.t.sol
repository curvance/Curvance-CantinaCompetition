// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseProtocolMessagingHub } from "../TestBaseProtocolMessagingHub.sol";
import { ERC20 } from "contracts/libraries/external/ERC20.sol";
import { ProtocolMessagingHub } from "contracts/architecture/ProtocolMessagingHub.sol";

contract BridgeCVETest is TestBaseProtocolMessagingHub {
    function setUp() public override {
        super.setUp();

        deal(address(cve), address(protocolMessagingHub), _ONE);
        deal(address(cve), _ONE);
    }

    function test_bridgeCVE_fail_whenCallerIsNotCVE() public {
        vm.expectRevert(
            ProtocolMessagingHub.ProtocolMessagingHub__Unauthorized.selector
        );
        protocolMessagingHub.bridgeCVE(137, user1, _ONE);
    }

    function test_bridgeCVE_fail_whenMessagingHubHasNoEnoughCVE() public {
        vm.prank(address(cve));

        vm.expectRevert(ERC20.InsufficientBalance.selector);
        protocolMessagingHub.bridgeCVE(137, user1, _ONE * 5);
    }

    function test_bridgeCVE_fail_whenDestinationChainIsNotRegistered() public {
        vm.prank(address(cve));

        vm.expectRevert();
        protocolMessagingHub.bridgeCVE(138, user1, _ONE);
    }

    function test_bridgeCVE_fail_whenRecipientIsZeroAddress() public {
        vm.prank(address(cve));

        vm.expectRevert();
        protocolMessagingHub.bridgeCVE(137, address(0), _ONE);
    }

    function test_bridgeCVE_success() public {
        uint256 messageFee = protocolMessagingHub.quoteWormholeFee(137, true);

        vm.prank(address(cve));

        protocolMessagingHub.bridgeCVE{ value: messageFee }(137, user1, _ONE);

        assertEq(cve.balanceOf(address(protocolMessagingHub)), 0);
        assertEq(cve.balanceOf(_TOKEN_BRIDGE), _ONE);
    }
}
