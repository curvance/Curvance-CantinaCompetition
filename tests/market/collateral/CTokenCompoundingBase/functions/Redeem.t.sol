// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseCTokenCompoundingBase } from "../TestBaseCTokenCompoundingBase.sol";
import { GaugeErrors } from "contracts/gauge/GaugeErrors.sol";

contract CTokenCompoundingBase_RedeemTest is TestBaseCTokenCompoundingBase {
    event Transfer(address indexed from, address indexed to, uint256 amount);

    function test_CTokenCompoundingBase_Redeem_fail_whenNoEnoughToRedeem() public {
        vm.prank(address(1));

        vm.expectRevert();
        cBALRETH.redeem(100);
    }

    function test_CTokenCompoundingBase_Redeem_fail_whenAmountIsZero() public {
        cBALRETH.mint(100);

        vm.expectRevert(GaugeErrors.InvalidAmount.selector);
        cBALRETH.redeem(0);
    }

    function test_CTokenCompoundingBase_Redeem_success() public {
        cBALRETH.mint(100);

        uint256 underlyingBalance = balRETH.balanceOf(address(this));
        uint256 balance = cBALRETH.balanceOf(address(this));
        uint256 totalSupply = cBALRETH.totalSupply();

        vm.expectEmit(true, true, true, true, address(cBALRETH));
        emit Transfer(address(this), address(0), 100);

        cBALRETH.redeem(100);

        assertEq(balRETH.balanceOf(address(this)), underlyingBalance + 100);
        assertEq(cBALRETH.balanceOf(address(this)), balance - 100);
        assertEq(cBALRETH.totalSupply(), totalSupply - 100);
    }
}
