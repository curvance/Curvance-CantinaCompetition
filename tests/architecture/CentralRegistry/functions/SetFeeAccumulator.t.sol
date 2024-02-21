// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { CentralRegistry } from "contracts/architecture/CentralRegistry.sol";

contract SetFeeAccumulatorTest is TestBaseMarket {
    event CoreContractSet(string indexed contractType, address newAddress);

    address public newFeeAccumulator = makeAddr("Fee Accumulator");

    function test_setFeeAccumulator_fail_whenUnauthorized() public {
        vm.prank(address(0));

        vm.expectRevert(
            CentralRegistry.CentralRegistry__Unauthorized.selector
        );
        centralRegistry.setFeeAccumulator(newFeeAccumulator);
    }

    function test_setFeeAccumulator_success() public {
        assertEq(centralRegistry.feeAccumulator(), address(feeAccumulator));

        vm.expectEmit(true, true, true, true);
        emit CoreContractSet("Fee Accumulator", newFeeAccumulator);

        centralRegistry.setFeeAccumulator(newFeeAccumulator);

        assertEq(centralRegistry.feeAccumulator(), newFeeAccumulator);
    }
}
