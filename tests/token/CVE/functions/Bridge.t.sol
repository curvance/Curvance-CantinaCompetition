// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { ERC20 } from "contracts/libraries/external/ERC20.sol";

contract BridgeTest is TestBaseMarket {
    function setUp() public override {
        super.setUp();

        deal(address(cve), user1, _ONE);
        deal(user1, _ONE);
    }

    function test_bridge_fail_whenUserHasNoEnoughCVE() public {
        vm.prank(user1);

        vm.expectRevert(ERC20.InsufficientBalance.selector);
        cve.bridge(137, user1, _ONE + 1);
    }

    function test_bridge_fail_whenDestinationChainIsNotRegistered() public {
        vm.prank(user1);

        vm.expectRevert();
        cve.bridge(138, user1, _ONE);
    }

    function test_bridge_fail_whenRecipientIsZeroAddress() public {
        vm.prank(user1);

        vm.expectRevert();
        cve.bridge(137, address(0), _ONE);
    }

    function test_bridge_success() public {
        uint256 messageFee = protocolMessagingHub.quoteWormholeFee(137, true);

        vm.prank(user1);

        cve.bridge{ value: messageFee }(137, user1, _ONE);

        assertEq(cve.balanceOf(user1), 0);
        assertEq(cve.balanceOf(_TOKEN_BRIDGE), _ONE);
    }
}
