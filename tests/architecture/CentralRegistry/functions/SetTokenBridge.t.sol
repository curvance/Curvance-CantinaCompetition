// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { CentralRegistry } from "contracts/architecture/CentralRegistry.sol";

contract SetTokenBridgeTest is TestBaseMarket {
    event TokenBridgeSet(address newAddress);

    address public newTokenBridge = makeAddr("Token Bridge");

    function test_setTokenBridge_fail_whenUnauthorized() public {
        vm.prank(address(0));

        vm.expectRevert(
            CentralRegistry.CentralRegistry__Unauthorized.selector
        );
        centralRegistry.setTokenBridge(newTokenBridge);
    }

    function test_setTokenBridge_success() public {
        assertEq(address(centralRegistry.tokenBridge()), _TOKEN_BRIDGE);

        vm.expectEmit(true, true, true, true);
        emit TokenBridgeSet(newTokenBridge);

        centralRegistry.setTokenBridge(newTokenBridge);

        assertEq(address(centralRegistry.tokenBridge()), newTokenBridge);
    }
}
