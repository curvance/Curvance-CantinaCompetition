// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseProtocolMessagingHub } from "../TestBaseProtocolMessagingHub.sol";
import { ProtocolMessagingHub } from "contracts/architecture/ProtocolMessagingHub.sol";

contract SendGaugeEmissionsTest is TestBaseProtocolMessagingHub {
    function test_sendGaugeEmissions_fail_whenCallerIsNotAuthorized() public {
        vm.expectRevert(
            ProtocolMessagingHub.ProtocolMessagingHub__Unauthorized.selector
        );
        protocolMessagingHub.sendGaugeEmissions(23, address(this), "");
    }

    function test_sendGaugeEmissions_fail_whenChainIsNotSupported() public {
        vm.expectRevert(
            ProtocolMessagingHub
                .ProtocolMessagingHub__ChainIsNotSupported
                .selector
        );

        vm.prank(address(feeAccumulator));
        protocolMessagingHub.sendGaugeEmissions(23, address(this), "");
    }

    function test_sendGaugeEmissions_fail_whenHasNoEnoughNativeAssetForGas()
        public
    {
        centralRegistry.addChainSupport(
            address(this),
            address(this),
            address(1),
            42161,
            1,
            1,
            23
        );

        vm.expectRevert();

        vm.prank(address(feeAccumulator));
        protocolMessagingHub.sendGaugeEmissions(23, address(this), "");
    }

    function test_sendGaugeEmissions_success() public {
        deal(address(protocolMessagingHub), _ONE);

        centralRegistry.addChainSupport(
            address(this),
            address(this),
            address(1),
            42161,
            1,
            1,
            23
        );

        vm.prank(address(feeAccumulator));
        protocolMessagingHub.sendGaugeEmissions(23, address(this), "");
    }
}
