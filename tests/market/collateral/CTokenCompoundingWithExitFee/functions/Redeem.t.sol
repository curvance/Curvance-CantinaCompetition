// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseCTokenCompoundingWithExitFee } from "../TestBaseCTokenCompoundingWithExitFee.sol";
import { CTokenCompounding } from "contracts/market/collateral/CTokenCompounding.sol";

contract CTokenCompoundingWithExitFeeRedeemTest is
    TestBaseCTokenCompoundingWithExitFee
{
    event Transfer(address indexed from, address indexed to, uint256 amount);

    function test_cTokenCompoundingWithExitFeeRedeem_fail_whenNoEnoughToRedeem()
        public
    {
        vm.prank(address(1));

        vm.expectRevert();
        cBALRETHWithExitFee.redeem(100, address(this), address(this));
    }

    function test_cTokenCompoundingWithExitFeeRedeem_fail_whenAmountIsZero()
        public
    {
        cBALRETHWithExitFee.mint(100, address(this));

        vm.expectRevert(
            CTokenCompounding.CTokenCompounding__ZeroAssets.selector
        );
        cBALRETHWithExitFee.redeem(0, address(this), address(this));
    }

    function test_cTokenCompoundingWithExitFeeRedeem_success() public {
        cBALRETHWithExitFee.mint(100, address(this));

        uint256 underlyingBalance = balRETH.balanceOf(address(this));
        uint256 balance = cBALRETHWithExitFee.balanceOf(address(this));
        uint256 totalSupply = cBALRETHWithExitFee.totalSupply();

        vm.expectEmit(true, true, true, true, address(cBALRETHWithExitFee));
        emit Transfer(address(this), address(0), 100);

        cBALRETHWithExitFee.redeem(100, address(this), address(this));

        assertEq(balRETH.balanceOf(address(this)), underlyingBalance + 98);
        assertEq(cBALRETHWithExitFee.balanceOf(address(this)), balance - 100);
        assertEq(cBALRETHWithExitFee.totalSupply(), totalSupply - 100);
    }
}
