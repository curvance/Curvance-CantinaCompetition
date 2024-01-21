// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseProtocolMessagingHub } from "../TestBaseProtocolMessagingHub.sol";
import { ProtocolMessagingHub } from "contracts/architecture/ProtocolMessagingHub.sol";

contract SendWormholeMessagesTest is TestBaseProtocolMessagingHub {
    function test_sendWormholeMessages_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.expectRevert(
            ProtocolMessagingHub.ProtocolMessagingHub__Unauthorized.selector
        );
        protocolMessagingHub.sendWormholeMessages(23, address(this), "");
    }

    function test_sendWormholeMessages_fail_whenChainIsNotSupported() public {
        vm.expectRevert(
            ProtocolMessagingHub
                .ProtocolMessagingHub__ChainIsNotSupported
                .selector
        );

        vm.prank(address(feeAccumulator));
        protocolMessagingHub.sendWormholeMessages(23, address(this), "");
    }

    function test_sendWormholeMessages_fail_whenNativeAssetIsNotEnough()
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
        protocolMessagingHub.sendWormholeMessages(23, address(this), "");
    }

    function test_sendWormholeMessages_success() public {
        uint256 messageFee = protocolMessagingHub.quoteWormholeFee(23, false);
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
            23,
            address(this),
            ""
        );
    }
}
