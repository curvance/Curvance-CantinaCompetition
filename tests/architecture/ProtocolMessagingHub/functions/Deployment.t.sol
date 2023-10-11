// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseProtocolMessagingHub } from "../TestBaseProtocolMessagingHub.sol";
import { ProtocolMessagingHub } from "contracts/architecture/ProtocolMessagingHub.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract ProtocolMessagingHubDeploymentTest is TestBaseProtocolMessagingHub {
    function test_protocolMessagingHubDeployment_fail_whenCentralRegistryIsInvalid()
        public
    {
        vm.expectRevert(
            ProtocolMessagingHub
                .ProtocolMessagingHub__ConfigurationError
                .selector
        );
        new ProtocolMessagingHub(
            ICentralRegistry(address(0)),
            _USDC_ADDRESS,
            _STARGATE_ROUTER
        );
    }

    function test_protocolMessagingHubDeployment_fail_whenFeeTokenIsZeroAddress()
        public
    {
        vm.expectRevert(
            ProtocolMessagingHub
                .ProtocolMessagingHub__FeeTokenIsZeroAddress
                .selector
        );
        new ProtocolMessagingHub(
            ICentralRegistry(address(centralRegistry)),
            address(0),
            _STARGATE_ROUTER
        );
    }

    function test_protocolMessagingHubDeployment_fail_whenStargateRouterIsZeroAddress()
        public
    {
        vm.expectRevert(
            ProtocolMessagingHub
                .ProtocolMessagingHub__StargateRouterIsZeroAddress
                .selector
        );
        new ProtocolMessagingHub(
            ICentralRegistry(address(centralRegistry)),
            _USDC_ADDRESS,
            address(0)
        );
    }

    function test_protocolMessagingHubDeployment_success() public {
        protocolMessagingHub = new ProtocolMessagingHub(
            ICentralRegistry(address(centralRegistry)),
            _USDC_ADDRESS,
            _STARGATE_ROUTER
        );

        assertEq(
            address(protocolMessagingHub.centralRegistry()),
            address(centralRegistry)
        );
        assertEq(
            address(protocolMessagingHub.CVE()),
            address(centralRegistry.CVE())
        );
        assertEq(protocolMessagingHub.feeToken(), _USDC_ADDRESS);
        assertEq(protocolMessagingHub.stargateRouter(), _STARGATE_ROUTER);
    }
}
