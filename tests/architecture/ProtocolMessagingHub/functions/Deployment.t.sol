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
            _WORMHOLE_CORE,
            _WORMHOLE_RELAYER,
            _CIRCLE_RELAYER,
            _TOKEN_BRIDGE_RELAYER
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
            _WORMHOLE_CORE,
            _WORMHOLE_RELAYER,
            _CIRCLE_RELAYER,
            _TOKEN_BRIDGE_RELAYER
        );
    }

    function test_protocolMessagingHubDeployment_fail_whenWormholeCoreIsZeroAddress()
        public
    {
        vm.expectRevert(
            ProtocolMessagingHub
                .ProtocolMessagingHub__WormholeCoreIsZeroAddress
                .selector
        );
        new ProtocolMessagingHub(
            ICentralRegistry(address(centralRegistry)),
            _USDC_ADDRESS,
            address(0),
            _WORMHOLE_RELAYER,
            _CIRCLE_RELAYER,
            _TOKEN_BRIDGE_RELAYER
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
            _WORMHOLE_CORE,
            address(0),
            _CIRCLE_RELAYER,
            _TOKEN_BRIDGE_RELAYER
        );
    }

    function test_protocolMessagingHubDeployment_fail_whenTokenBridgeRelayerIsZeroAddress()
        public
    {
        vm.expectRevert(
            ProtocolMessagingHub
                .ProtocolMessagingHub__TokenBridgeRelayerIsZeroAddress
                .selector
        );
        new ProtocolMessagingHub(
            ICentralRegistry(address(centralRegistry)),
            _USDC_ADDRESS,
            _WORMHOLE_CORE,
            _WORMHOLE_RELAYER,
            _CIRCLE_RELAYER,
            address(0)
        );
    }

    function test_protocolMessagingHubDeployment_success() public {
        protocolMessagingHub = new ProtocolMessagingHub(
            ICentralRegistry(address(centralRegistry)),
            _USDC_ADDRESS,
            _WORMHOLE_CORE,
            _WORMHOLE_RELAYER,
            _CIRCLE_RELAYER,
            _TOKEN_BRIDGE_RELAYER
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
        assertEq(address(protocolMessagingHub.wormholeCore()), _WORMHOLE_CORE);
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
