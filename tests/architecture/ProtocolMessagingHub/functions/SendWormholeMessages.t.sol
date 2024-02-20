// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseProtocolMessagingHub } from "../TestBaseProtocolMessagingHub.sol";
import { ProtocolMessagingHub } from "contracts/architecture/ProtocolMessagingHub.sol";

contract ProtocolMessagingHubSendWormholeMessagesTest is
    TestBaseProtocolMessagingHub
{
    function test_protocolMessagingHubSendWormholeMessages_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.expectRevert(
            ProtocolMessagingHub.ProtocolMessagingHub__Unauthorized.selector
        );
        protocolMessagingHub.sendWormholeMessages(42161, address(this), "");
    }

    function test_protocolMessagingHubSendWormholeMessages_fail_whenMessagingHubIsPaused()
        public
    {
        protocolMessagingHub.flipMessagingHubStatus();

        vm.prank(address(feeAccumulator));

        vm.expectRevert(
            ProtocolMessagingHub
                .ProtocolMessagingHub__MessagingHubPaused
                .selector
        );
        protocolMessagingHub.sendWormholeMessages(42161, address(this), "");
    }

    function test_protocolMessagingHubSendWormholeMessages_fail_whenChainIsNotSupported()
        public
    {
        vm.expectRevert(
            ProtocolMessagingHub
                .ProtocolMessagingHub__ChainIsNotSupported
                .selector
        );

        vm.prank(address(feeAccumulator));
        protocolMessagingHub.sendWormholeMessages(42161, address(this), "");
    }

    function test_protocolMessagingHubSendWormholeMessages_fail_whenNativeAssetIsNotEnough()
        public
    {
        centralRegistry.addChainSupport(
            address(this),
            address(this),
            address(1),
            42161,
            1,
            1,
            23
        );

        vm.expectRevert();

        vm.prank(address(feeAccumulator));
        protocolMessagingHub.sendWormholeMessages(42161, address(this), "");
    }

    function test_protocolMessagingHubSendWormholeMessages_success() public {
        uint256 messageFee = protocolMessagingHub.quoteWormholeFee(
            42161,
            false
        );
        deal(address(feeAccumulator), messageFee);

        centralRegistry.addChainSupport(
            address(this),
            address(this),
            address(1),
            42161,
            1,
            1,
            23
        );

        vm.prank(address(feeAccumulator));
        protocolMessagingHub.sendWormholeMessages{ value: messageFee }(
            42161,
            address(this),
            ""
        );
    }
}
