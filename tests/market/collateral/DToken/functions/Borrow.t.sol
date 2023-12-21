// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseDToken } from "../TestBaseDToken.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";
import { DToken } from "contracts/market/collateral/DToken.sol";

contract DTokenBorrowTest is TestBaseDToken {
    event Borrow(address borrower, uint256 borrowAmount);

    function test_dTokenBorrow_fail_whenBorrowIsNotAllowed() public {
        lendtroller.setBorrowPaused(address(dUSDC), true);

        vm.expectRevert();
        dUSDC.borrow(100e6);
    }

    function test_dTokenBorrow_fail_whenBorrowAmountExceedsCash() public {
        uint256 cash = dUSDC.marketUnderlyingHeld();

        vm.expectRevert(
            Lendtroller.Lendtroller__InsufficientCollateral.selector
        );
        dUSDC.borrow(cash + 1);
    }

    function test_dTokenBorrow_success() public {
        _setCbalRETHCollateralCaps(100_000e18);

        deal(_USDC_ADDRESS, address(dUSDC), 2000e6);

        lendtroller.postCollateral(address(this), address(cBALRETH), 1e18 - 1);

        uint256 underlyingBalance = usdc.balanceOf(address(this));
        uint256 balance = dUSDC.balanceOf(address(this));
        uint256 totalSupply = dUSDC.totalSupply();
        uint256 totalBorrows = dUSDC.totalBorrows();

        dUSDC.borrow(100e6);

        assertEq(usdc.balanceOf(address(this)), underlyingBalance + 100e6);
        assertEq(dUSDC.balanceOf(address(this)), balance);
        assertEq(dUSDC.totalSupply(), totalSupply);
        assertEq(dUSDC.totalBorrows(), totalBorrows + 100e6);
    }
}
