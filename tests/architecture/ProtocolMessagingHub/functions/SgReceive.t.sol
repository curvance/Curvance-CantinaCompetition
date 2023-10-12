// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseProtocolMessagingHub } from "../TestBaseProtocolMessagingHub.sol";
import { ProtocolMessagingHub } from "contracts/architecture/ProtocolMessagingHub.sol";

contract SgReceiveTest is TestBaseProtocolMessagingHub {
    function test_sgReceive_fail_whenCallerIsNotStargateRouter() public {
        vm.expectRevert(
            ProtocolMessagingHub
            .ProtocolMessagingHub__Unauthorized
            .selector
        );
        protocolMessagingHub.sgReceive(
            110,
            abi.encodePacked(address(this)),
            0,
            _USDC_ADDRESS,
            100,
            ""
        );
    }

    function test_sgReceive_fail_whenNotReceivedToken() public {
        vm.expectRevert();

        vm.prank(_STARGATE_ROUTER);
        protocolMessagingHub.sgReceive(
            110,
            abi.encodePacked(address(this)),
            0,
            _USDC_ADDRESS,
            100e6,
            ""
        );
    }

    function test_sgReceive_success() public {
        deal(_USDC_ADDRESS, address(protocolMessagingHub), 100e6);

        assertEq(usdc.balanceOf(address(protocolMessagingHub)), 100e6);
        assertEq(usdc.balanceOf(address(feeAccumulator)), 0);

        vm.prank(_STARGATE_ROUTER);
        protocolMessagingHub.sgReceive(
            110,
            abi.encodePacked(address(this)),
            0,
            _USDC_ADDRESS,
            100e6,
            ""
        );

        assertEq(usdc.balanceOf(address(protocolMessagingHub)), 0);
        assertEq(usdc.balanceOf(address(feeAccumulator)), 100e6);
    }
}
