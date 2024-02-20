// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { CentralRegistry } from "contracts/architecture/CentralRegistry.sol";

contract SetProtocolMessagingHubTest is TestBaseMarket {
    event CoreContractSet(string indexed contractType, address newAddress);

    address public newProtocolMessagingHub =
        makeAddr("Protocol Messaging Hub");

    function test_setProtocolMessagingHub_fail_whenUnauthorized() public {
        vm.prank(address(0));

        vm.expectRevert(
            CentralRegistry.CentralRegistry__Unauthorized.selector
        );
        centralRegistry.setProtocolMessagingHub(newProtocolMessagingHub);
    }

    function test_setProtocolMessagingHub_success() public {
        assertEq(
            centralRegistry.protocolMessagingHub(),
            address(protocolMessagingHub)
        );

        vm.expectEmit(true, true, true, true);
        emit CoreContractSet(
            "Protocol Messaging Hub",
            newProtocolMessagingHub
        );

        centralRegistry.setProtocolMessagingHub(newProtocolMessagingHub);

        assertEq(
            centralRegistry.protocolMessagingHub(),
            newProtocolMessagingHub
        );
    }
}
