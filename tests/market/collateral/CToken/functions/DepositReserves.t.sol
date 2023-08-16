// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseCToken } from "../TestBaseCToken.sol";

contract CTokenDepositReservesTest is TestBaseCToken {
    function test_cTokenDepositReserves_fail_whenCallIsNotAuthorized() public {
        vm.prank(address(1));

        vm.expectRevert("CToken: UNAUTHORIZED");
        cBALRETH.depositReserves(100);
    }

    function test_cTokenDepositReserves_fail_whenAmountIsZero() public {
        vm.expectRevert("BasePositionVault: ZERO_SHARES");
        cBALRETH.depositReserves(0);
    }

    function test_cTokenDepositReserves_success() public {
        uint256 underlyingBalance = balRETH.balanceOf(address(this));
        uint256 balance = cBALRETH.balanceOf(address(this));
        uint256 totalSupply = cBALRETH.totalSupply();

        cBALRETH.depositReserves(100);

        assertEq(balRETH.balanceOf(address(this)), underlyingBalance - 100);
        assertEq(cBALRETH.balanceOf(address(this)), balance);
        assertEq(cBALRETH.totalSupply(), totalSupply);
    }
}
