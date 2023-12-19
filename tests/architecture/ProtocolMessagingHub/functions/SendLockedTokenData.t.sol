// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseProtocolMessagingHub } from "../TestBaseProtocolMessagingHub.sol";
import { ProtocolMessagingHub } from "contracts/architecture/ProtocolMessagingHub.sol";

contract SendLockedTokenDataTest is TestBaseProtocolMessagingHub {
    function test_sendLockedTokenData_fail_whenCallerIsNotAuthorized() public {
        vm.expectRevert(
            ProtocolMessagingHub.ProtocolMessagingHub__Unauthorized.selector
        );
        protocolMessagingHub.sendLockedTokenData(23, address(this), "", 0);
    }

    function test_sendLockedTokenData_fail_whenChainIsNotSupported() public {
        vm.expectRevert(
            ProtocolMessagingHub
                .ProtocolMessagingHub__ChainIsNotSupported
                .selector
        );

        vm.prank(address(feeAccumulator));
        protocolMessagingHub.sendLockedTokenData(23, address(this), "", 0);
    }

    function test_sendLockedTokenData_fail_whenMsgValueIsInvalid() public {
        centralRegistry.addChainSupport(
            address(this),
            address(this),
            address(1),
            42161,
            1,
            1,
            23
        );

        vm.expectRevert(
            ProtocolMessagingHub.ProtocolMessagingHub__InvalidMsgValue.selector
        );

        vm.prank(address(feeAccumulator));
        protocolMessagingHub.sendLockedTokenData(23, address(this), "", 1);
    }

    function test_sendLockedTokenData_success() public {
        (uint256 messageFee, ) = protocolMessagingHub.quoteWormholeFee(
            23,
            false
        );
        deal(address(feeAccumulator), messageFee);

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
        protocolMessagingHub.sendLockedTokenData{ value: messageFee }(
            23,
            address(this),
            "",
            messageFee
        );
    }
}
