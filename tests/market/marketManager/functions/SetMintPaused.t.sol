// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseMarketManager } from "../TestBaseMarketManager.sol";
import { MarketManager } from "contracts/market/MarketManager.sol";

contract SetMintPausedTest is TestBaseMarketManager {
    event TokenActionPaused(address mToken, string action, bool pauseState);

    function test_setMintPaused_fail_whenCallerIsNotAuthorized() public {
        vm.prank(address(1));

        vm.expectRevert(MarketManager.MarketManager__Unauthorized.selector);
        marketManager.setMintPaused(address(dUSDC), true);
    }

    function test_setMintPaused_fail_whenMTokenIsNotListed() public {
        vm.expectRevert(MarketManager.MarketManager__TokenNotListed.selector);
        marketManager.canMint(address(dUSDC));

        vm.expectRevert(MarketManager.MarketManager__TokenNotListed.selector);
        marketManager.setMintPaused(address(dUSDC), true);
    }

    function test_setMintPaused_success() public {
        marketManager.listToken(address(dUSDC));

        marketManager.canMint(address(dUSDC));

        assertEq(marketManager.mintPaused(address(dUSDC)), 0);

        vm.expectEmit(true, true, true, true, address(marketManager));
        emit TokenActionPaused(address(dUSDC), "Mint Paused", true);

        marketManager.setMintPaused(address(dUSDC), true);

        vm.expectRevert(MarketManager.MarketManager__Paused.selector);
        marketManager.canMint(address(dUSDC));

        assertEq(marketManager.mintPaused(address(dUSDC)), 2);

        vm.expectEmit(true, true, true, true, address(marketManager));
        emit TokenActionPaused(address(dUSDC), "Mint Paused", false);

        marketManager.setMintPaused(address(dUSDC), false);

        assertEq(marketManager.mintPaused(address(dUSDC)), 1);
    }
}
