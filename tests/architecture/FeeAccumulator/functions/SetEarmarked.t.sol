// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseFeeAccumulator } from "../TestBaseFeeAccumulator.sol";

contract SetEarmarkedTest is TestBaseFeeAccumulator {
    function test_setEarmarked_fail_whenCallerIsNotAuthorized() public {
        vm.prank(user1);

        vm.expectRevert("FeeAccumulator: UNAUTHORIZED");
        feeAccumulator.setEarmarked(_WETH_ADDRESS, true);
    }

    function test_setEarmarked_success() public {
        (, uint256 forOTC) = feeAccumulator.rewardTokenInfo(_WETH_ADDRESS);
        assertEq(forOTC, 0);

        feeAccumulator.setEarmarked(_WETH_ADDRESS, true);

        (, forOTC) = feeAccumulator.rewardTokenInfo(_WETH_ADDRESS);
        assertEq(forOTC, 2);

        feeAccumulator.setEarmarked(_WETH_ADDRESS, false);

        (, forOTC) = feeAccumulator.rewardTokenInfo(_WETH_ADDRESS);
        assertEq(forOTC, 1);
    }
}
