// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseFeeAccumulator } from "../TestBaseFeeAccumulator.sol";
import { FeeAccumulator } from "contracts/architecture/FeeAccumulator.sol";

contract ExecuteOTCTest is TestBaseFeeAccumulator {
    function test_executeOTC_fail_whenCallerIsNotAuthorized() public {
        vm.prank(user1);

        vm.expectRevert(FeeAccumulator.FeeAccumulator__Unauthorized.selector);
        feeAccumulator.executeOTC(_WETH_ADDRESS, _ONE);
    }

    function test_executeOTC_fail_whenTokenIsNotEarmarked() public {
        vm.expectRevert(FeeAccumulator.FeeAccumulator__EarmarkError.selector);
        feeAccumulator.executeOTC(_WETH_ADDRESS, _ONE);
    }

    function test_executeOTC_fail_whenFeeTokenIsNotApproved() public {
        feeAccumulator.setEarmarked(_WETH_ADDRESS, true);

        vm.expectRevert();
        feeAccumulator.executeOTC(_WETH_ADDRESS, _ONE);
    }

    function test_executeOTC_fail_whenGelatoOneBalanceIsInvalid() public {
        feeAccumulator.setEarmarked(_WETH_ADDRESS, true);

        usdc.approve(address(feeAccumulator), _ONE);

        vm.expectRevert();
        feeAccumulator.executeOTC(_WETH_ADDRESS, _ONE);
    }
}
