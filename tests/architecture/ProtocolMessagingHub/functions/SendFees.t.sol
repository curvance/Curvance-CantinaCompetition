// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseProtocolMessagingHub } from "../TestBaseProtocolMessagingHub.sol";
import { FeeTokenBridgingHub } from "contracts/architecture/FeeTokenBridgingHub.sol";
import { ProtocolMessagingHub } from "contracts/architecture/ProtocolMessagingHub.sol";

contract SendFeesTest is TestBaseProtocolMessagingHub {
    function test_sendFees_fail_whenCallerIsNotAuthorized() public {
        vm.expectRevert(
            ProtocolMessagingHub.ProtocolMessagingHub__Unauthorized.selector
        );
        protocolMessagingHub.sendFees(23, address(this), 10e6);
    }

    function test_sendFees_fail_whenOperatorIsNotAuthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ProtocolMessagingHub
                    .ProtocolMessagingHub__OperatorIsNotAuthorized
                    .selector,
                address(this),
                0
            )
        );

        vm.prank(address(feeAccumulator));
        protocolMessagingHub.sendFees(23, address(this), 10e6);
    }

    function test_sendFees_fail_whenHasNoEnoughNativeAssetForMessageFee()
        public
    {
        deal(_USDC_ADDRESS, address(feeAccumulator), _ONE);

        centralRegistry.addChainSupport(
            address(this),
            address(this),
            address(cve),
            42161,
            1,
            1,
            23
        );

        vm.expectRevert(
            FeeTokenBridgingHub
                .FeeTokenBridgingHub__InsufficientGasToken
                .selector
        );

        vm.prank(address(feeAccumulator));
        protocolMessagingHub.sendFees(23, address(this), 10e6);
    }

    function test_sendFees_fail_whenHasNoEnoughFeeToken() public {
        deal(address(protocolMessagingHub), _ONE);

        centralRegistry.addChainSupport(
            address(this),
            address(this),
            address(cve),
            42161,
            1,
            1,
            23
        );

        vm.expectRevert(bytes4(keccak256("TransferFromFailed()")));

        vm.prank(address(feeAccumulator));
        protocolMessagingHub.sendFees(23, address(this), 10e6);
    }

    function test_sendFees_success() public {
        deal(address(protocolMessagingHub), _ONE);
        deal(_USDC_ADDRESS, address(feeAccumulator), _ONE);

        centralRegistry.addChainSupport(
            address(this),
            address(this),
            address(cve),
            42161,
            1,
            1,
            23
        );

        assertEq(usdc.balanceOf(address(feeAccumulator)), _ONE);

        vm.prank(address(feeAccumulator));
        protocolMessagingHub.sendFees(23, address(this), 10e6);

        assertEq(usdc.balanceOf(address(feeAccumulator)), _ONE - 10e6);
    }
}
