// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseProtocolMessagingHub } from "../TestBaseProtocolMessagingHub.sol";
import { ITokenBridgeRelayer } from "contracts/interfaces/wormhole/ITokenBridgeRelayer.sol";
import { ERC20 } from "contracts/libraries/external/ERC20.sol";
import { ProtocolMessagingHub } from "contracts/architecture/ProtocolMessagingHub.sol";

contract BridgeCVETest is TestBaseProtocolMessagingHub {
    ITokenBridgeRelayer public tokenBridgeRelayer =
        ITokenBridgeRelayer(_TOKEN_BRIDGE_RELAYER);

    uint256[] public chainIDs;
    uint16[] public wormholeChainIDs;

    function setUp() public override {
        super.setUp();

        chainIDs.push(1);
        wormholeChainIDs.push(2);
        chainIDs.push(137);
        wormholeChainIDs.push(5);

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

        deal(address(cve), address(protocolMessagingHub), _ONE);
    }

    function test_bridgeCVE_fail_whenCallerIsNotCVE() public {
        vm.expectRevert(
            ProtocolMessagingHub.ProtocolMessagingHub__Unauthorized.selector
        );
        protocolMessagingHub.bridgeCVE(137, user1, _ONE);
    }

    function test_bridgeCVE_fail_whenMessagingHubHasNoEnoughCVE() public {
        vm.prank(address(cve));

        vm.expectRevert(ERC20.InsufficientBalance.selector);
        protocolMessagingHub.bridgeCVE(137, user1, _ONE * 5);
    }

    function test_bridgeCVE_fail_whenDestinationChainIsNotRegistered() public {
        vm.prank(address(cve));

        vm.expectRevert("target not registered");
        protocolMessagingHub.bridgeCVE(138, user1, _ONE);
    }

    function test_bridgeCVE_fail_whenRecipientIsZeroAddress() public {
        vm.prank(address(cve));

        vm.expectRevert("targetRecipient cannot be bytes32(0)");
        protocolMessagingHub.bridgeCVE(137, address(0), _ONE);
    }

    function test_bridgeCVE_fail_whenAmountIsNotEnoughToCoverFee() public {
        uint256 relayerFee = cve.relayerFee(137);

        vm.prank(address(cve));

        vm.expectRevert("insufficient amount");
        protocolMessagingHub.bridgeCVE(137, user1, relayerFee - 1);
    }

    function test_bridgeCVE_success() public {
        vm.prank(address(cve));

        protocolMessagingHub.bridgeCVE(137, user1, _ONE);

        assertEq(cve.balanceOf(address(protocolMessagingHub)), 0);
        assertEq(cve.balanceOf(tokenBridgeRelayer.tokenBridge()), _ONE);
    }
}
