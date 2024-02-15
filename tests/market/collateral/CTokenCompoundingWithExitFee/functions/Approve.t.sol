// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseCTokenCompoundingWithExitFee } from "../TestBaseCTokenCompoundingWithExitFee.sol";

contract CTokenCompoundingWithExitFeeApproveTest is
    TestBaseCTokenCompoundingWithExitFee
{
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 amount
    );

    function test_CTokenCompoundingWithExitFeeApprove_success() public {
        uint256 allowance = cBALRETHWithExitFee.allowance(
            address(this),
            user1
        );

        vm.expectEmit(true, true, true, true, address(cBALRETHWithExitFee));
        emit Approval(address(this), user1, 100);

        cBALRETHWithExitFee.approve(user1, 100);

        assertEq(
            cBALRETHWithExitFee.allowance(address(this), user1),
            allowance + 100
        );
    }
}
