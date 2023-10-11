// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseProtocolMessagingHub } from "../TestBaseProtocolMessagingHub.sol";
import { ProtocolMessagingHub } from "contracts/architecture/ProtocolMessagingHub.sol";

contract OnOFTReceivedTest is TestBaseProtocolMessagingHub {
    function test_onOFTReceived_fail_whenCallerIsNotCVE() public {
        vm.expectRevert("ProtocolMessagingHub: UNAUTHORIZED");
        protocolMessagingHub.onOFTReceived(
            110,
            abi.encodePacked(address(cve)),
            0,
            bytes32(bytes20(address(this))),
            _ONE,
            ""
        );
    }

    function test_onOFTReceived_success() public {
        centralRegistry.addChainSupport(
            address(this),
            address(this),
            abi.encodePacked(address(cve)),
            110,
            1,
            1,
            110
        );

        vm.prank(address(cve));
        protocolMessagingHub.onOFTReceived(
            110,
            abi.encodePacked(address(cve)),
            0,
            bytes32(bytes20(address(this))),
            _ONE,
            ""
        );
    }
}
