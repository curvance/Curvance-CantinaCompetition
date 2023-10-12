// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseProtocolMessagingHub } from "../TestBaseProtocolMessagingHub.sol";
import { ProtocolMessagingHub } from "contracts/architecture/ProtocolMessagingHub.sol";
import { PoolData } from "contracts/interfaces/IProtocolMessagingHub.sol";
import { LzTxObj } from "contracts/interfaces/layerzero/IStargateRouter.sol";

contract SendFeesTest is TestBaseProtocolMessagingHub {
    function test_sendFees_fail_whenCallerIsNotAuthorized() public {
        vm.expectRevert(ProtocolMessagingHub.ProtocolMessagingHub__Unauthorized.selector);
        protocolMessagingHub.sendFees(
            address(this),
            PoolData({
                dstChainId: 110,
                srcPoolId: 1,
                dstPoolId: 1,
                amountLD: 10e6,
                minAmountLD: 9e6
            }),
            LzTxObj({
                dstGasForCall: 0,
                dstNativeAmount: 0,
                dstNativeAddr: ""
            }),
            ""
        );
    }

    function test_sendFees_fail_whenOperatorIsNotAuthorized() public {
        vm.expectRevert(
            ProtocolMessagingHub
                .ProtocolMessagingHub__ConfigurationError
                .selector
        );

        vm.prank(address(feeAccumulator));
        protocolMessagingHub.sendFees(
            address(this),
            PoolData({
                dstChainId: 110,
                srcPoolId: 1,
                dstPoolId: 1,
                amountLD: 10e6,
                minAmountLD: 9e6
            }),
            LzTxObj({
                dstGasForCall: 0,
                dstNativeAmount: 0,
                dstNativeAddr: ""
            }),
            ""
        );
    }

    function test_sendFees_fail_whenChainIdsNotMatch() public {
        centralRegistry.addChainSupport(
            address(this),
            address(this),
            abi.encodePacked(address(cve)),
            110,
            1,
            1,
            42161
        );

        vm.expectRevert(
            ProtocolMessagingHub
                .ProtocolMessagingHub__ConfigurationError
                .selector
        );

        vm.prank(address(feeAccumulator));
        protocolMessagingHub.sendFees(
            address(this),
            PoolData({
                dstChainId: 110,
                srcPoolId: 1,
                dstPoolId: 1,
                amountLD: 10e6,
                minAmountLD: 9e6
            }),
            LzTxObj({
                dstGasForCall: 0,
                dstNativeAmount: 0,
                dstNativeAddr: ""
            }),
            ""
        );
    }

    function test_sendFees_fail_whenHasNoEnoughNativeAssetForMessageFee()
        public
    {
        centralRegistry.addChainSupport(
            address(this),
            address(this),
            abi.encodePacked(address(cve)),
            110,
            1,
            1,
            110
        );

        vm.expectRevert(
            ProtocolMessagingHub
                .ProtocolMessagingHub__InsufficientGasToken
                .selector
        );

        vm.prank(address(feeAccumulator));
        protocolMessagingHub.sendFees(
            address(this),
            PoolData({
                dstChainId: 110,
                srcPoolId: 1,
                dstPoolId: 1,
                amountLD: 10e6,
                minAmountLD: 9e6
            }),
            LzTxObj({
                dstGasForCall: 0,
                dstNativeAmount: 0,
                dstNativeAddr: ""
            }),
            ""
        );
    }

    function test_sendFees_fail_whenHasNoEnoughFeeToken() public {
        deal(address(protocolMessagingHub), _ONE);

        centralRegistry.addChainSupport(
            address(this),
            address(this),
            abi.encodePacked(address(cve)),
            110,
            1,
            1,
            110
        );

        vm.expectRevert(bytes4(keccak256("TransferFromFailed()")));

        vm.prank(address(feeAccumulator));
        protocolMessagingHub.sendFees(
            address(this),
            PoolData({
                dstChainId: 110,
                srcPoolId: 1,
                dstPoolId: 1,
                amountLD: 10e6,
                minAmountLD: 9e6
            }),
            LzTxObj({
                dstGasForCall: 0,
                dstNativeAmount: 0,
                dstNativeAddr: ""
            }),
            ""
        );
    }

    function test_sendFees_success() public {
        deal(address(protocolMessagingHub), _ONE);
        deal(_USDC_ADDRESS, address(feeAccumulator), _ONE);

        centralRegistry.addChainSupport(
            address(this),
            address(this),
            abi.encodePacked(address(cve)),
            110,
            1,
            1,
            110
        );

        assertEq(usdc.balanceOf(address(feeAccumulator)), _ONE);

        vm.prank(address(feeAccumulator));
        protocolMessagingHub.sendFees(
            address(this),
            PoolData({
                dstChainId: 110,
                srcPoolId: 1,
                dstPoolId: 1,
                amountLD: 10e6,
                minAmountLD: 9e6
            }),
            LzTxObj({
                dstGasForCall: 0,
                dstNativeAmount: 0,
                dstNativeAddr: ""
            }),
            ""
        );

        assertEq(usdc.balanceOf(address(feeAccumulator)), _ONE - 10e6);
    }
}
