// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { CentralRegistry } from "contracts/architecture/CentralRegistry.sol";

contract SetExternalCallDataCheckerTest is TestBaseMarket {
    address public externalCallDataChecker = makeAddr("CallData Checker");

    function test_setExternalCallDataChecker_fail_whenUnauthorized() public {
        vm.prank(address(0));

        vm.expectRevert(
            CentralRegistry.CentralRegistry__Unauthorized.selector
        );
        centralRegistry.setExternalCallDataChecker(
            address(1),
            externalCallDataChecker
        );
    }

    function test_setExternalCallDataChecker_success() public {
        assertEq(
            centralRegistry.externalCallDataChecker(address(1)),
            address(0)
        );

        centralRegistry.setExternalCallDataChecker(
            address(1),
            externalCallDataChecker
        );

        assertEq(
            centralRegistry.externalCallDataChecker(address(1)),
            externalCallDataChecker
        );
    }
}
