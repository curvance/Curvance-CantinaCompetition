// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseCToken } from "../TestBaseCToken.sol";

contract CTokenWithdrawReservesTest is TestBaseCToken {
    function test_cTokenWithdrawReserves_fail_whenCallIsNotAuthorized()
        public
    {
        vm.prank(address(1));

        vm.expectRevert("CToken: UNAUTHORIZED");
        cBALRETH.withdrawReserves(100);
    }

    function test_cTokenWithdrawReserves_fail_whenAmountIsZero() public {
        vm.expectRevert();
        cBALRETH.withdrawReserves(0);
    }

    function test_cTokenWithdrawReserves_whenAmountExceedsTotalReserves()
        public
    {
        uint256 totalReserves = cBALRETH.totalReserves();

        vm.expectRevert();
        cBALRETH.withdrawReserves(totalReserves + 1);
    }

    function test_cTokenWithdrawReserves_success() public {
        cBALRETH.depositReserves(100);

        uint256 underlyingBalance = balRETH.balanceOf(address(this));
        uint256 balance = cBALRETH.balanceOf(address(this));
        uint256 totalSupply = cBALRETH.totalSupply();

        cBALRETH.withdrawReserves(100);

        assertEq(balRETH.balanceOf(address(this)), underlyingBalance + 100);
        assertEq(cBALRETH.balanceOf(address(this)), balance);
        assertEq(cBALRETH.totalSupply(), totalSupply);
    }
}
