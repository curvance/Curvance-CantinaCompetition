// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseCToken } from "../TestBaseCToken.sol";

contract CTokenRedeemUnderlyingTest is TestBaseCToken {
    event Transfer(address indexed from, address indexed to, uint256 amount);

    function test_cTokenRedeemUnderlying_fail_whenNoEnoughToRedeem() public {
        vm.prank(address(1));

        vm.expectRevert();
        cBALRETH.redeemUnderlying(100);
    }

    function test_cTokenRedeemUnderlying_fail_whenAmountIsZero() public {
        cBALRETH.mint(100);

        vm.expectRevert();
        cBALRETH.redeemUnderlying(0);
    }

    function test_cTokenRedeemUnderlying_success() public {
        cBALRETH.mint(100);

        uint256 underlyingBalance = balRETH.balanceOf(address(this));
        uint256 balance = cBALRETH.balanceOf(address(this));
        uint256 totalSupply = cBALRETH.totalSupply();

        vm.expectEmit(true, true, true, true, address(cBALRETH));
        emit Transfer(address(this), address(cBALRETH), 100);

        cBALRETH.redeemUnderlying(100);

        assertEq(balRETH.balanceOf(address(this)), underlyingBalance + 100);
        assertEq(cBALRETH.balanceOf(address(this)), balance - 100);
        assertEq(cBALRETH.totalSupply(), totalSupply - 100);
    }
}
