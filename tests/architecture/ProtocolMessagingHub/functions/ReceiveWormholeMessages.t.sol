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
        vm.prank(_WORMHOLE_RELAYER);

        vm.expectRevert();
        protocolMessagingHub.receiveWormholeMessages(
            abi.encode(1, bytes32(uint256(uint160(_USDC_ADDRESS))), 100e6),
            new bytes[](0),
            bytes32(uint256(uint160(address(srcMessagingHub)))),
            23,
            bytes32("0x01")
        );
    }

    function test_protocolMessagingHubReceiveWormholeMessages_fail_whenMessagingHubIsPaused()
        public
    {
        protocolMessagingHub.flipMessagingHubStatus();

        vm.prank(_WORMHOLE_RELAYER);

        vm.expectRevert(
            ProtocolMessagingHub
                .ProtocolMessagingHub__MessagingHubPaused
                .selector
        );
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

    function test_protocolMessagingHubReceiveWormholeMessages_success_whenPayloadIdIs1()
        public
    {
        deal(_USDC_ADDRESS, address(protocolMessagingHub), 100e6);

        vm.prank(_WORMHOLE_RELAYER);
        protocolMessagingHub.receiveWormholeMessages(
            abi.encode(1, bytes32(uint256(uint160(_USDC_ADDRESS))), 100e6),
            new bytes[](0),
            bytes32(0),
            23,
            bytes32("0x01")
        );

        assertEq(usdc.balanceOf(address(protocolMessagingHub)), 100e6);
        assertEq(usdc.balanceOf(address(cveLocker)), 0);

        vm.prank(_WORMHOLE_RELAYER);
        protocolMessagingHub.receiveWormholeMessages(
            abi.encode(1, bytes32(uint256(uint160(_USDC_ADDRESS))), 100e6),
            new bytes[](0),
            bytes32(uint256(uint160(address(srcMessagingHub)))),
            23,
            bytes32("0x02")
        );

        assertEq(usdc.balanceOf(address(protocolMessagingHub)), 0);
        assertEq(usdc.balanceOf(address(cveLocker)), 100e6);
    }

    function test_protocolMessagingHubReceiveWormholeMessages_success_whenPayloadIdIs4()
        public
    {
        address[] memory gaugePools;
        uint256[] memory emissionTotals;
        address[][] memory tokens;
        uint256[][] memory emissions;
        uint256 chainLockedAmount = _ONE;
        uint256 messageType = 1;

        vm.expectRevert();
        feeAccumulator.crossChainLockData(0);

        uint256 nextEpoch = cveLocker.nextEpochToDeliver();

        vm.prank(_WORMHOLE_RELAYER);
        protocolMessagingHub.receiveWormholeMessages(
            abi.encode(
                4,
                abi.encode(
                    gaugePools,
                    emissionTotals,
                    tokens,
                    emissions,
                    chainLockedAmount,
                    messageType
                )
            ),
            new bytes[](0),
            bytes32(uint256(uint160(address(srcMessagingHub)))),
            23,
            bytes32("0x01")
        );

        (uint224 lockAmount, uint16 epoch, uint16 chainId) = feeAccumulator
            .crossChainLockData(0);

        assertEq(lockAmount, _ONE);
        assertEq(chainId, 42161);
        assertEq(epoch, nextEpoch);

        messageType = 2;

        assertEq(cveLocker.epochRewardsPerCVE(nextEpoch), 0);

        vm.prank(_WORMHOLE_RELAYER);
        protocolMessagingHub.receiveWormholeMessages(
            abi.encode(
                4,
                abi.encode(
                    gaugePools,
                    emissionTotals,
                    tokens,
                    emissions,
                    chainLockedAmount,
                    messageType
                )
            ),
            new bytes[](0),
            bytes32(uint256(uint160(address(srcMessagingHub)))),
            23,
            bytes32("0x02")
        );

        assertEq(cveLocker.epochRewardsPerCVE(nextEpoch), _ONE);
        assertEq(cveLocker.nextEpochToDeliver(), nextEpoch + 1);
    }

    function test_protocolMessagingHubReceiveWormholeMessages_success_whenPayloadIdIs5()
        public
    {
        centralRegistry.addVeCVELocker(address(protocolMessagingHub));

        assertEq(cve.balanceOf(address(protocolMessagingHub)), 0);
        assertEq(veCVE.balanceOf(user1), 0);

        address recipient = user1;
        uint256 amount = _ONE;
        bool continuousLock = true;

        vm.prank(_WORMHOLE_RELAYER);
        protocolMessagingHub.receiveWormholeMessages(
            abi.encode(5, abi.encode(recipient, amount, continuousLock)),
            new bytes[](0),
            bytes32(uint256(uint160(address(srcMessagingHub)))),
            23,
            bytes32("0x01")
        );

        assertEq(cve.balanceOf(address(protocolMessagingHub)), 0);
        assertEq(veCVE.balanceOf(user1), amount);
    }
}
