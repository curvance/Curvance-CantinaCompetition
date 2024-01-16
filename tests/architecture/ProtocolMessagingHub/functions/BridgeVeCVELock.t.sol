// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseProtocolMessagingHub } from "../TestBaseProtocolMessagingHub.sol";
import { ITokenBridgeRelayer } from "contracts/interfaces/external/wormhole/ITokenBridgeRelayer.sol";
import { ProtocolMessagingHub } from "contracts/architecture/ProtocolMessagingHub.sol";

contract BridgeVeCVELockTest is TestBaseProtocolMessagingHub {
    ITokenBridgeRelayer public tokenBridgeRelayer =
        ITokenBridgeRelayer(_TOKEN_BRIDGE_RELAYER);

    uint256[] public chainIDs;
    uint16[] public wormholeChainIDs;

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

        chainIDs.push(1);
        wormholeChainIDs.push(2);
        chainIDs.push(42161);
        wormholeChainIDs.push(23);

        protocolMessagingHub.registerWormholeChainIDs(
            chainIDs,
            wormholeChainIDs
        );

        ITokenBridgeRelayer.SwapRateUpdate[]
            memory swapRateUpdate = new ITokenBridgeRelayer.SwapRateUpdate[](
                1
            );
        swapRateUpdate[0] = ITokenBridgeRelayer.SwapRateUpdate({
            token: address(cve),
            value: 10e8
        });

        vm.startPrank(tokenBridgeRelayer.owner());
        tokenBridgeRelayer.registerToken(2, address(cve));
        tokenBridgeRelayer.updateSwapRate(2, swapRateUpdate);
        vm.stopPrank();

        deal(address(veCVE), _ONE);
    }

    function test_bridgeVeCVELock_fail_whenCallerIsNotVeCVE() public {
        vm.expectRevert(
            ProtocolMessagingHub.ProtocolMessagingHub__Unauthorized.selector
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
        uint256 messageFee = protocolMessagingHub.quoteWormholeFee(23, false);

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
        uint256 messageFee = protocolMessagingHub.quoteWormholeFee(23, false);

        vm.prank(address(veCVE));

        protocolMessagingHub.bridgeVeCVELock{ value: messageFee }(
            42161,
            user1,
            _ONE,
            true
        );
    }
}
