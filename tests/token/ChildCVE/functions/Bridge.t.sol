// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseChildCVE } from "../TestBaseChildCVE.sol";
import { ITokenBridgeRelayer } from "contracts/interfaces/external/wormhole/ITokenBridgeRelayer.sol";
import { ERC20 } from "contracts/libraries/external/ERC20.sol";

contract BridgeTest is TestBaseChildCVE {
    ITokenBridgeRelayer public tokenBridgeRelayer =
        ITokenBridgeRelayer(_TOKEN_BRIDGE_RELAYER);

    uint256[] public chainIDs;
    uint16[] public wormholeChainIDs;

    function setUp() public override {
        super.setUp();

        centralRegistry.setCVE(address(childCVE));
        _deployProtocolMessagingHub();

        chainIDs.push(1);
        wormholeChainIDs.push(2);
        chainIDs.push(137);
        wormholeChainIDs.push(5);

        centralRegistry.registerWormholeChainIDs(chainIDs, wormholeChainIDs);

        ITokenBridgeRelayer.SwapRateUpdate[]
            memory swapRateUpdate = new ITokenBridgeRelayer.SwapRateUpdate[](
                1
            );
        swapRateUpdate[0] = ITokenBridgeRelayer.SwapRateUpdate({
            token: address(childCVE),
            value: 10e8
        });

        vm.startPrank(tokenBridgeRelayer.owner());
        tokenBridgeRelayer.registerToken(2, address(childCVE));
        tokenBridgeRelayer.updateSwapRate(2, swapRateUpdate);
        vm.stopPrank();

        vm.prank(centralRegistry.protocolMessagingHub());
        childCVE.mintGaugeEmissions(user1, _ONE);
    }

    function test_bridge_fail_whenUserHasNoEnoughCVE() public {
        vm.prank(user1);

        vm.expectRevert(ERC20.InsufficientBalance.selector);
        childCVE.bridge(137, user1, _ONE + 1);
    }

    function test_bridge_fail_whenDestinationChainIsNotRegistered() public {
        vm.prank(user1);

        vm.expectRevert("target not registered");
        childCVE.bridge(138, user1, _ONE);
    }

    function test_bridge_fail_whenRecipientIsZeroAddress() public {
        vm.prank(user1);

        vm.expectRevert("targetRecipient cannot be bytes32(0)");
        childCVE.bridge(137, address(0), _ONE);
    }

    function test_bridge_fail_whenAmountIsNotEnoughToCoverFee() public {
        uint256 relayerFee = childCVE.relayerFee(137);

        vm.prank(user1);

        vm.expectRevert("insufficient amount");
        childCVE.bridge(137, user1, relayerFee - 1);
    }

    function test_bridge_success() public {
        vm.prank(user1);

        childCVE.bridge(137, user1, _ONE);

        assertEq(childCVE.balanceOf(user1), 0);
        assertEq(childCVE.balanceOf(tokenBridgeRelayer.tokenBridge()), _ONE);
    }
}
