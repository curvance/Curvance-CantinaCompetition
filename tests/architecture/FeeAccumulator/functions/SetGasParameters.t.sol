// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseFeeAccumulator } from "../TestBaseFeeAccumulator.sol";
import { FeeAccumulator } from "contracts/architecture/FeeAccumulator.sol";

contract SetGasParametersTest is TestBaseFeeAccumulator {
    bytes32 internal constant _GAS_FOR_CALLDATA_SLOT = bytes32(uint256(3));
    bytes32 internal constant _GAS_FOR_CROSS_CHAIN_SLOT = bytes32(uint256(4));

    function test_setGasParameters_fail_whenCallerIsNotAuthorized() public {
        vm.prank(user1);

        vm.expectRevert(FeeAccumulator.FeeAccumulator__Unauthorized.selector);
        feeAccumulator.setGasParameters(1e9, 1e9);
    }

    function test_setGasParameters_success() public {
        feeAccumulator.setGasParameters(1e9, 1e9);

        assertEq(
            uint256(vm.load(address(feeAccumulator), _GAS_FOR_CALLDATA_SLOT)),
            1e9
        );
        assertEq(
            uint256(
                vm.load(address(feeAccumulator), _GAS_FOR_CROSS_CHAIN_SLOT)
            ),
            1e9
        );
    }
}
