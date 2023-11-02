// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseProtocolMessagingHub } from "../TestBaseProtocolMessagingHub.sol";
import { ProtocolMessagingHub } from "contracts/architecture/ProtocolMessagingHub.sol";

contract SetStargateAddressTest is TestBaseProtocolMessagingHub {
    function test_protocolMessagingHubDeployment_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.prank(user1);
        vm.expectRevert(ProtocolMessagingHub.ProtocolMessagingHub__Unauthorized.selector);
        protocolMessagingHub.setStargateAddress(address(1));
    }

    function test_protocolMessagingHubDeployment_fail_whenStargateRouterIsZeroAddress()
        public
    {
        vm.expectRevert(
            ProtocolMessagingHub
                .ProtocolMessagingHub__StargateRouterIsZeroAddress
                .selector
        );
        protocolMessagingHub.setStargateAddress(address(0));
    }

    function test_protocolMessagingHubDeployment_success() public {
        address newStargateRouter = makeAddr("NewStargateRouter");
        protocolMessagingHub.setStargateAddress(newStargateRouter);

        assertEq(protocolMessagingHub.stargateRouter(), newStargateRouter);
    }
}
