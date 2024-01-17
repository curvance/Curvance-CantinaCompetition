// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseMarketManager } from "../TestBaseMarketManager.sol";
import { MarketManager } from "contracts/market/MarketManager.sol";

contract SetBorrowPausedTest is TestBaseMarketManager {
    event TokenActionPaused(address mToken, string action, bool pauseState);

    function test_setBorrowPaused_fail_whenCallerIsNotAuthorized() public {
        vm.prank(address(1));

        vm.expectRevert(MarketManager.MarketManager__Unauthorized.selector);
        marketManager.setBorrowPaused(address(dUSDC), true);
    }

    function test_setBorrowPaused_fail_whenMTokenIsNotListed() public {
        vm.expectRevert(MarketManager.MarketManager__TokenNotListed.selector);
        marketManager.setBorrowPaused(address(dUSDC), true);
    }

    function test_setBorrowPaused_success() public {
        marketManager.listToken(address(dUSDC));

        assertEq(marketManager.borrowPaused(address(dUSDC)), 0);

        vm.expectEmit(true, true, true, true, address(marketManager));
        emit TokenActionPaused(address(dUSDC), "Borrow Paused", true);

        marketManager.setBorrowPaused(address(dUSDC), true);

        assertEq(marketManager.borrowPaused(address(dUSDC)), 2);

        vm.expectEmit(true, true, true, true, address(marketManager));
        emit TokenActionPaused(address(dUSDC), "Borrow Paused", false);

        marketManager.setBorrowPaused(address(dUSDC), false);

        assertEq(marketManager.borrowPaused(address(dUSDC)), 1);
    }
}
