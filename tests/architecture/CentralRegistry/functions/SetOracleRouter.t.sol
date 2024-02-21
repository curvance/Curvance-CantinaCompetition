// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { CentralRegistry } from "contracts/architecture/CentralRegistry.sol";

contract SetOracleRouterTest is TestBaseMarket {
    event CoreContractSet(string indexed contractType, address newAddress);

    address public newOracleRouter = makeAddr("Oracle Router");

    function test_setOracleRouter_fail_whenUnauthorized() public {
        vm.prank(address(0));

        vm.expectRevert(
            CentralRegistry.CentralRegistry__Unauthorized.selector
        );
        centralRegistry.setOracleRouter(newOracleRouter);
    }

    function test_setOracleRouter_success() public {
        assertEq(centralRegistry.oracleRouter(), address(oracleRouter));

        vm.expectEmit(true, true, true, true);
        emit CoreContractSet("Oracle Router", newOracleRouter);

        centralRegistry.setOracleRouter(newOracleRouter);

        assertEq(centralRegistry.oracleRouter(), newOracleRouter);
    }
}
