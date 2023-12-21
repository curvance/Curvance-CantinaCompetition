// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseDToken } from "../TestBaseDToken.sol";

contract DTokenApproveTest is TestBaseDToken {
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 amount
    );

    function test_dTokenApprove_success() public {
        uint256 allowance = dUSDC.allowance(address(this), user1);

        vm.expectEmit(true, true, true, true, address(dUSDC));
        emit Approval(address(this), user1, 100e6);

        dUSDC.approve(user1, 100e6);

        assertEq(dUSDC.allowance(address(this), user1), allowance + 100e6);
    }
}
