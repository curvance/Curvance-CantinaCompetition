// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseProtocolMessagingHub } from "../TestBaseProtocolMessagingHub.sol";
import { ITokenBridge } from "contracts/interfaces/external/wormhole/ITokenBridge.sol";
import { ProtocolMessagingHub } from "contracts/architecture/ProtocolMessagingHub.sol";

contract BridgeVeCVELockTest is TestBaseProtocolMessagingHub {
    ITokenBridge public tokenBridge = ITokenBridge(_TOKEN_BRIDGE);

    function setUp() public override {
        super.setUp();

        centralRegistry.addChainSupport(
            address(this),
            address(protocolMessagingHub),
            address(cve),
            42161,
            1,
            1,
            23
        );

        deal(address(veCVE), _ONE);
    }

    function test_bridgeVeCVELock_fail_whenCallerIsNotVeCVE() public {
        vm.expectRevert(
            ProtocolMessagingHub.ProtocolMessagingHub__Unauthorized.selector
        );
        protocolMessagingHub.bridgeVeCVELock(42161, user1, _ONE, true);
    }

    function test_bridgeVeCVELock_fail_whenMessagingHubIsPaused() public {
        protocolMessagingHub.flipMessagingHubStatus();

        vm.prank(address(veCVE));

        vm.expectRevert(
            ProtocolMessagingHub
                .ProtocolMessagingHub__MessagingHubPaused
                .selector
        );
        protocolMessagingHub.bridgeVeCVELock(42161, user1, _ONE, true);
    }

    function test_bridgeVeCVELock_fail_whenDestinationChainIsNotRegistered()
        public
    {
        vm.prank(address(veCVE));

        vm.expectRevert(
            ProtocolMessagingHub
                .ProtocolMessagingHub__ChainIsNotSupported
                .selector
        );
        protocolMessagingHub.bridgeVeCVELock(138, user1, _ONE, true);
    }

    function test_bridgeVeCVELock_fail_whenNativeTokenIsNotEnoughToCoverFee()
        public
    {
        uint256 messageFee = protocolMessagingHub.quoteWormholeFee(
            42161,
            false
        );

        vm.prank(address(veCVE));

        vm.expectRevert();
        protocolMessagingHub.bridgeVeCVELock{ value: messageFee - 1 }(
            42161,
            user1,
            _ONE,
            true
        );
    }

    function test_bridgeVeCVELock_success() public {
        uint256 messageFee = protocolMessagingHub.quoteWormholeFee(
            42161,
            false
        );

        vm.prank(address(veCVE));

        protocolMessagingHub.bridgeVeCVELock{ value: messageFee }(
            42161,
            user1,
            _ONE,
            true
        );
    }
}
