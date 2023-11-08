// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseLendtroller } from "../TestBaseLendtroller.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";
import { IMToken } from "contracts/interfaces/market/IMToken.sol";

contract SetBorrowPausedTest is TestBaseLendtroller {
    event ActionPaused(IMToken mToken, string action, bool pauseState);

    function test_setBorrowPaused_fail_whenCallerIsNotAuthorized() public {
        vm.prank(address(1));

        vm.expectRevert(Lendtroller.Lendtroller__Unauthorized.selector);
        lendtroller.setBorrowPaused(IMToken(address(dUSDC)), true);
    }

    function test_setBorrowPaused_fail_whenMTokenIsNotListed() public {
        vm.expectRevert(Lendtroller.Lendtroller__TokenNotListed.selector);
        lendtroller.setBorrowPaused(IMToken(address(dUSDC)), true);
    }

    function test_setBorrowPaused_success() public {
        lendtroller.listToken(address(dUSDC));

        assertEq(lendtroller.borrowPaused(address(dUSDC)), 0);

        vm.expectEmit(true, true, true, true, address(lendtroller));
        emit ActionPaused(IMToken(address(dUSDC)), "Borrow Paused", true);

        lendtroller.setBorrowPaused(IMToken(address(dUSDC)), true);

        assertEq(lendtroller.borrowPaused(address(dUSDC)), 2);

        vm.expectEmit(true, true, true, true, address(lendtroller));
        emit ActionPaused(IMToken(address(dUSDC)), "Borrow Paused", false);

        lendtroller.setBorrowPaused(IMToken(address(dUSDC)), false);

        assertEq(lendtroller.borrowPaused(address(dUSDC)), 1);
    }
}
