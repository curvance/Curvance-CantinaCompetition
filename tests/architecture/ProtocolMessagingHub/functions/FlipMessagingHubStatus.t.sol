// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseProtocolMessagingHub } from "../TestBaseProtocolMessagingHub.sol";
import { ProtocolMessagingHub } from "contracts/architecture/ProtocolMessagingHub.sol";

contract FlipMessagingHubStatusTest is TestBaseProtocolMessagingHub {
    function test_flipMessagingHubStatus_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.prank(user1);

        vm.expectRevert(
            ProtocolMessagingHub.ProtocolMessagingHub__Unauthorized.selector
        );
        protocolMessagingHub.flipMessagingHubStatus();

        protocolMessagingHub.flipMessagingHubStatus();

        vm.prank(user1);

        vm.expectRevert(
            ProtocolMessagingHub.ProtocolMessagingHub__Unauthorized.selector
        );
        protocolMessagingHub.flipMessagingHubStatus();
    }

    function test_flipMessagingHubStatus_success() public {
        assertEq(protocolMessagingHub.isPaused(), 0);

        protocolMessagingHub.flipMessagingHubStatus();

        assertEq(protocolMessagingHub.isPaused(), 2);

        protocolMessagingHub.flipMessagingHubStatus();

        assertEq(protocolMessagingHub.isPaused(), 1);
    }
}
