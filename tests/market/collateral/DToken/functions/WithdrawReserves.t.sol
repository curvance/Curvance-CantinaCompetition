// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseDToken } from "../TestBaseDToken.sol";
import { DToken } from "contracts/market/collateral/DToken.sol";

contract DTokenWithdrawReservesTest is TestBaseDToken {
    function test_dTokenWithdrawReserves_fail_whenCallIsNotAuthorized()
        public
    {
        vm.prank(address(1));

        vm.expectRevert(DToken.DToken__Unauthorized.selector);
        dUSDC.withdrawReserves(100e6);
    }

    function test_dTokenWithdrawReserves_fail_whenAmountIsZero() public {
        vm.expectRevert();
        dUSDC.withdrawReserves(0);
    }

    function test_dTokenWithdrawReserves_whenAmountExceedsTotalReserves()
        public
    {
        uint256 totalReserves = dUSDC.totalReserves();

        vm.expectRevert();
        dUSDC.withdrawReserves(totalReserves + 1);
    }

    function test_dTokenWithdrawReserves_success() public {
        dUSDC.depositReserves(100e6);

        uint256 underlyingBalance = usdc.balanceOf(address(this));
        uint256 balance = dUSDC.balanceOf(address(this));
        uint256 totalSupply = dUSDC.totalSupply();

        dUSDC.withdrawReserves(100e6);

        assertEq(usdc.balanceOf(address(this)), underlyingBalance + 100e6);
        assertEq(dUSDC.balanceOf(address(this)), balance);
        assertEq(dUSDC.totalSupply(), totalSupply);
    }
}
