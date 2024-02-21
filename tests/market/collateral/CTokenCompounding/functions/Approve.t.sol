// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseCTokenCompounding } from "../TestBaseCTokenCompounding.sol";

contract CTokenCompoundingApproveTest is TestBaseCTokenCompounding {
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 amount
    );

    function test_cTokenCompoundingApprove_success() public {
        uint256 allowance = cBALRETH.allowance(address(this), user1);

        vm.expectEmit(true, true, true, true, address(cBALRETH));
        emit Approval(address(this), user1, 100);

        cBALRETH.approve(user1, 100);

        assertEq(cBALRETH.allowance(address(this), user1), allowance + 100);
    }
}
