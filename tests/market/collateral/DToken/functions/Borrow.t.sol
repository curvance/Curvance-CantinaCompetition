// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseDToken } from "../TestBaseDToken.sol";
import { DToken } from "contracts/market/collateral/DToken.sol";
import { IMToken } from "contracts/interfaces/market/IMToken.sol";

contract DTokenBorrowTest is TestBaseDToken {
    event Borrow(address borrower, uint256 borrowAmount);

    function test_dTokenBorrow_fail_whenBorrowIsNotAllowed() public {
        lendtroller.setBorrowPaused(IMToken(address(dUSDC)), true);

        vm.expectRevert();
        dUSDC.borrow(100e6);
    }

    function test_dTokenBorrow_fail_whenBorrowAmountExceedsCash() public {
        uint256 cash = dUSDC.getCash();

        vm.expectRevert(DToken.DToken__CashNotAvailable.selector);
        dUSDC.borrow(cash + 1);
    }

    function test_dTokenBorrow_success() public {
        dUSDC.mint(100e6);

        uint256 underlyingBalance = usdc.balanceOf(address(this));
        uint256 balance = dUSDC.balanceOf(address(this));
        uint256 totalSupply = dUSDC.totalSupply();
        uint256 totalBorrows = dUSDC.totalBorrows();

        vm.expectEmit(true, true, true, true, address(dUSDC));
        emit Borrow(address(this), 100e6);

        dUSDC.borrow(100e6);

        assertEq(usdc.balanceOf(address(this)), underlyingBalance + 100e6);
        assertEq(dUSDC.balanceOf(address(this)), balance);
        assertEq(dUSDC.totalSupply(), totalSupply);
        assertEq(dUSDC.totalBorrows(), totalBorrows + 100e6);
    }
}
