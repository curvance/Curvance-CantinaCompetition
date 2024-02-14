// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseProtocolMessagingHub } from "../TestBaseProtocolMessagingHub.sol";
import { ProtocolMessagingHub } from "contracts/architecture/ProtocolMessagingHub.sol";

contract ProtocolMessagingHubReceiveWormholeMessagesTest is
    TestBaseProtocolMessagingHub
{
    address public srcMessagingHub;

    function setUp() public override {
        super.setUp();

        srcMessagingHub = makeAddr("SrcMessagingHub");

        centralRegistry.addChainSupport(
            address(srcMessagingHub),
            address(srcMessagingHub),
            address(cve),
            42161,
            1,
            1,
            23
        );
    }

    function test_protocolMessagingHubReceiveWormholeMessages_fail_whenCallerIsNotWormholeRelayer()
        public
    {
        vm.expectRevert(
            ProtocolMessagingHub.ProtocolMessagingHub__Unauthorized.selector
        );
        protocolMessagingHub.receiveWormholeMessages(
            abi.encode(1, bytes32(uint256(uint160(_USDC_ADDRESS))), 100e6),
            new bytes[](0),
            bytes32(uint256(uint160(address(srcMessagingHub)))),
            23,
            bytes32("0x01")
        );
    }

    function test_protocolMessagingHubReceiveWormholeMessages_fail_whenNotReceivedToken()
        public
    {
        vm.expectRevert();

        vm.prank(_WORMHOLE_RELAYER);
        protocolMessagingHub.receiveWormholeMessages(
            abi.encode(1, bytes32(uint256(uint160(_USDC_ADDRESS))), 100e6),
            new bytes[](0),
            bytes32(uint256(uint160(address(srcMessagingHub)))),
            23,
            bytes32("0x01")
        );
    }

    function test_protocolMessagingHubReceiveWormholeMessages_fail_whenMessageIsAlreadyDelivered()
        public
    {
        deal(_USDC_ADDRESS, address(protocolMessagingHub), 100e6);

        vm.prank(_WORMHOLE_RELAYER);
        protocolMessagingHub.receiveWormholeMessages(
            abi.encode(1, bytes32(uint256(uint160(_USDC_ADDRESS))), 100e6),
            new bytes[](0),
            bytes32(uint256(uint160(address(srcMessagingHub)))),
            23,
            bytes32("0x01")
        );

        vm.prank(_WORMHOLE_RELAYER);

        vm.expectRevert(
            abi.encodeWithSelector(
                ProtocolMessagingHub
                    .ProtocolMessagingHub__MessageHashIsAlreadyDelivered
                    .selector,
                bytes32("0x01")
            )
        );
        protocolMessagingHub.receiveWormholeMessages(
            abi.encode(1, bytes32(uint256(uint160(_USDC_ADDRESS))), 100e6),
            new bytes[](0),
            bytes32(uint256(uint160(address(srcMessagingHub)))),
            23,
            bytes32("0x01")
        );
    }

    function test_protocolMessagingHubReceiveWormholeMessages_success()
        public
    {
        deal(_USDC_ADDRESS, address(protocolMessagingHub), 100e6);

        assertEq(usdc.balanceOf(address(protocolMessagingHub)), 100e6);
        assertEq(usdc.balanceOf(address(cveLocker)), 0);

        vm.prank(_WORMHOLE_RELAYER);
        protocolMessagingHub.receiveWormholeMessages(
            abi.encode(1, bytes32(uint256(uint160(_USDC_ADDRESS))), 100e6),
            new bytes[](0),
            bytes32(uint256(uint160(address(srcMessagingHub)))),
            23,
            bytes32("0x01")
        );

        assertEq(usdc.balanceOf(address(protocolMessagingHub)), 0);
        assertEq(usdc.balanceOf(address(cveLocker)), 100e6);
    }
}
