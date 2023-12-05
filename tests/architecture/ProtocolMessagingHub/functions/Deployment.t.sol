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
                .ProtocolMessagingHub__InvalidCentralRegistry
                .selector
        );
        new ProtocolMessagingHub(
            ICentralRegistry(address(0)),
            _USDC_ADDRESS,
            _WORMHOLE_RELAYER,
            _CIRCLE_RELAYER
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
            _WORMHOLE_RELAYER,
            _CIRCLE_RELAYER
        );
    }

    function test_protocolMessagingHubDeployment_fail_whenWormholeRelayerIsZeroAddress()
        public
    {
        vm.expectRevert(
            ProtocolMessagingHub
                .ProtocolMessagingHub__WormholeRelayerIsZeroAddress
                .selector
        );
        new ProtocolMessagingHub(
            ICentralRegistry(address(centralRegistry)),
            _USDC_ADDRESS,
            address(0),
            _CIRCLE_RELAYER
        );
    }

    function test_protocolMessagingHubDeployment_fail_whenCircleRelayerIsZeroAddress()
        public
    {
        vm.expectRevert(
            ProtocolMessagingHub
                .ProtocolMessagingHub__CircleRelayerIsZeroAddress
                .selector
        );
        new ProtocolMessagingHub(
            ICentralRegistry(address(centralRegistry)),
            _USDC_ADDRESS,
            _WORMHOLE_RELAYER,
            address(0)
        );
    }

    function test_protocolMessagingHubDeployment_success() public {
        protocolMessagingHub = new ProtocolMessagingHub(
            ICentralRegistry(address(centralRegistry)),
            _USDC_ADDRESS,
            _WORMHOLE_RELAYER,
            _CIRCLE_RELAYER
        );

        assertEq(
            address(protocolMessagingHub.centralRegistry()),
            address(centralRegistry)
        );
        assertEq(
            address(protocolMessagingHub.cve()),
            address(centralRegistry.cve())
        );
        assertEq(protocolMessagingHub.feeToken(), _USDC_ADDRESS);
        assertEq(address(protocolMessagingHub.wormhole()), _WORMHOLE);
        assertEq(
            address(protocolMessagingHub.wormholeRelayer()),
            _WORMHOLE_RELAYER
        );
        assertEq(
            address(protocolMessagingHub.circleRelayer()),
            _CIRCLE_RELAYER
        );
    }
}
