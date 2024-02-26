// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { CentralRegistry } from "contracts/architecture/CentralRegistry.sol";

contract SetCircleTokenMessengerTest is TestBaseMarket {
    event CircleTokenMessengerSet(address newAddress);

    address public newCircleTokenMessenger =
        makeAddr("Circle Token Messenger");

    function test_setCircleTokenMessenger_fail_whenUnauthorized() public {
        vm.prank(address(0));

        vm.expectRevert(
            CentralRegistry.CentralRegistry__Unauthorized.selector
        );
        centralRegistry.setCircleTokenMessenger(newCircleTokenMessenger);
    }

    function test_setCircleTokenMessenger_success() public {
        assertEq(
            address(centralRegistry.circleTokenMessenger()),
            _CIRCLE_TOKEN_MESSENGER
        );

        vm.expectEmit(true, true, true, true);
        emit CircleTokenMessengerSet(newCircleTokenMessenger);

        centralRegistry.setCircleTokenMessenger(newCircleTokenMessenger);

        assertEq(
            address(centralRegistry.circleTokenMessenger()),
            newCircleTokenMessenger
        );
    }
}
