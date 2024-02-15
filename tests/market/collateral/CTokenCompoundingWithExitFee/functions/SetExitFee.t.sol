// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseCTokenCompoundingWithExitFee } from "../TestBaseCTokenCompoundingWithExitFee.sol";
import { CTokenBase } from "contracts/market/collateral/CTokenBase.sol";
import { CTokenCompoundingWithExitFee } from "contracts/market/collateral/CTokenCompoundingWithExitFee.sol";

contract CTokenCompoundingWithExitFeeSetExitFeeTest is
    TestBaseCTokenCompoundingWithExitFee
{
    event ExitFeeSet(uint256 oldExitFee, uint256 newExitFee);

    function test_cTokenCompoundingWithExitFeeSetExitFee_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.prank(user1);

        vm.expectRevert(CTokenBase.CTokenBase__Unauthorized.selector);
        cBALRETHWithExitFee.setExitFee(100);
    }

    function test_cTokenCompoundingWithExitFeeSetExitFee_fail_whenExitFeeExceedsMaximum()
        public
    {
        vm.expectRevert(
            CTokenCompoundingWithExitFee
                .CTokenCompoundingWithExitFee__InvalidExitFee
                .selector
        );
        cBALRETHWithExitFee.setExitFee(201);
    }

    function test_cTokenCompoundingWithExitFeeSetExitFee_success() public {
        uint256 exitFee = cBALRETHWithExitFee.exitFee();

        vm.expectEmit(true, true, true, true, address(cBALRETHWithExitFee));
        emit ExitFeeSet(exitFee, 0.01e18);

        cBALRETHWithExitFee.setExitFee(100);

        assertEq(cBALRETHWithExitFee.exitFee(), 0.01e18);
    }
}
