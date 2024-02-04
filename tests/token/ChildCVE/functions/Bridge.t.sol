// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseChildCVE } from "../TestBaseChildCVE.sol";
import { ERC20 } from "contracts/libraries/external/ERC20.sol";

contract BridgeTest is TestBaseChildCVE {
    function setUp() public override {
        super.setUp();

        centralRegistry.setCVE(address(childCVE));
        _deployProtocolMessagingHub();

        vm.prank(centralRegistry.protocolMessagingHub());
        childCVE.mintGaugeEmissions(user1, _ONE);

        deal(user1, _ONE);
    }

    function test_bridge_fail_whenUserHasNoEnoughCVE() public {
        vm.prank(user1);

        vm.expectRevert(ERC20.InsufficientBalance.selector);
        childCVE.bridge(137, user1, _ONE + 1);
    }

    function test_bridge_fail_whenDestinationChainIsNotRegistered() public {
        vm.prank(user1);

        vm.expectRevert();
        childCVE.bridge(138, user1, _ONE);
    }

    function test_bridge_fail_whenRecipientIsZeroAddress() public {
        vm.prank(user1);

        vm.expectRevert();
        childCVE.bridge(137, address(0), _ONE);
    }

    function test_bridge_success() public {
        uint256 messageFee = protocolMessagingHub.quoteWormholeFee(137, true);

        vm.prank(user1);

        childCVE.bridge{ value: messageFee }(137, user1, _ONE);

        assertEq(childCVE.balanceOf(user1), 0);
        assertEq(childCVE.balanceOf(_TOKEN_BRIDGE), _ONE);
    }
}
