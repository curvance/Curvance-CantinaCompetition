// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseProtocolMessagingHub } from "../TestBaseProtocolMessagingHub.sol";
import { ProtocolMessagingHub } from "contracts/architecture/ProtocolMessagingHub.sol";
import { LzCallParams } from "contracts/interfaces/ICVE.sol";

contract SendGaugeEmissionsTest is TestBaseProtocolMessagingHub {
    function test_sendGaugeEmissions_fail_whenCallerIsNotAuthorized() public {
        vm.expectRevert(
            ProtocolMessagingHub.ProtocolMessagingHub__Unauthorized.selector
        );
        protocolMessagingHub.sendGaugeEmissions(
            110,
            bytes32(bytes20(address(this))),
            "",
            1e9,
            LzCallParams({
                refundAddress: payable(address(this)),
                zroPaymentAddress: address(0),
                adapterParams: abi.encodePacked(uint16(1), uint256(1e9))
            })
        );
    }

    function test_sendGaugeEmissions_fail_whenChainIsNotSupported() public {
        vm.expectRevert(
            ProtocolMessagingHub
                .ProtocolMessagingHub__ChainIsNotSupported
                .selector
        );

        vm.prank(address(feeAccumulator));
        protocolMessagingHub.sendGaugeEmissions(
            110,
            bytes32(bytes20(address(this))),
            "",
            1e9,
            LzCallParams({
                refundAddress: payable(address(this)),
                zroPaymentAddress: address(0),
                adapterParams: abi.encodePacked(uint16(1), uint256(1e9))
            })
        );
    }

    function test_sendGaugeEmissions_fail_whenHasNoEnoughNativeAssetForGas()
        public
    {
        centralRegistry.addChainSupport(
            address(this),
            address(this),
            abi.encodePacked(address(1)),
            110,
            1,
            1,
            110
        );

        vm.expectRevert();

        vm.prank(address(feeAccumulator));
        protocolMessagingHub.sendGaugeEmissions(
            110,
            bytes32(bytes20(address(this))),
            "",
            1e9,
            LzCallParams({
                refundAddress: payable(address(this)),
                zroPaymentAddress: address(0),
                adapterParams: abi.encodePacked(uint16(1), uint256(1e9))
            })
        );
    }

    function test_sendGaugeEmissions_success() public {
        deal(address(protocolMessagingHub), _ONE);

        centralRegistry.addChainSupport(
            address(this),
            address(this),
            abi.encodePacked(address(1)),
            110,
            1,
            1,
            110
        );

        vm.prank(address(feeAccumulator));
        protocolMessagingHub.sendGaugeEmissions(
            110,
            bytes32(bytes20(address(this))),
            "",
            1e9,
            LzCallParams({
                refundAddress: payable(address(this)),
                zroPaymentAddress: address(0),
                adapterParams: abi.encodePacked(uint16(1), uint256(1e9))
            })
        );
    }
}
