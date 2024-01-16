// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { ITokenBridgeRelayer } from "contracts/interfaces/external/wormhole/ITokenBridgeRelayer.sol";
import { ERC20 } from "contracts/libraries/ERC20.sol";

contract BridgeTest is TestBaseMarket {
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

        deal(address(cve), user1, _ONE);
    }

    function test_bridge_fail_whenUserHasNoEnoughCVE() public {
        vm.prank(user1);

        vm.expectRevert(ERC20.InsufficientBalance.selector);
        cve.bridge(137, user1, _ONE + 1);
    }

    function test_bridge_fail_whenDestinationChainIsNotRegistered() public {
        vm.prank(user1);

        vm.expectRevert("target not registered");
        cve.bridge(138, user1, _ONE);
    }

    function test_bridge_fail_whenRecipientIsZeroAddress() public {
        vm.prank(user1);

        vm.expectRevert("targetRecipient cannot be bytes32(0)");
        cve.bridge(137, address(0), _ONE);
    }

    function test_bridge_fail_whenAmountIsNotEnoughToCoverFee() public {
        uint256 relayerFee = cve.relayerFee(137);

        vm.prank(user1);

        vm.expectRevert("insufficient amount");
        cve.bridge(137, user1, relayerFee - 1);
    }

    function test_bridge_success() public {
        vm.prank(user1);

        cve.bridge(137, user1, _ONE);

        assertEq(cve.balanceOf(user1), 0);
        assertEq(cve.balanceOf(tokenBridgeRelayer.tokenBridge()), _ONE);
    }
}
