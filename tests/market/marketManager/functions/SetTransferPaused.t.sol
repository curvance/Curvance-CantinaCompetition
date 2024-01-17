// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseMarketManager } from "../TestBaseMarketManager.sol";
import { MarketManager } from "contracts/market/MarketManager.sol";

contract SetTransferPausedTest is TestBaseMarketManager {
    event ActionPaused(string action, bool pauseState);

    function test_setTransferPaused_fail_whenCallerIsNotAuthorized() public {
        vm.prank(address(1));

        vm.expectRevert(MarketManager.MarketManager__Unauthorized.selector);
        marketManager.setTransferPaused(true);
    }

    function test_setTransferPaused_success() public {
        marketManager.listToken(address(dUSDC));

        marketManager.canTransfer(address(dUSDC), address(this), 1);

        assertEq(marketManager.transferPaused(), 1);

        vm.expectEmit(true, true, true, true, address(marketManager));
        emit ActionPaused("Transfer Paused", true);

        marketManager.setTransferPaused(true);

        vm.expectRevert(MarketManager.MarketManager__Paused.selector);
        marketManager.canTransfer(address(dUSDC), address(this), 1);

        assertEq(marketManager.transferPaused(), 2);

        vm.expectEmit(true, true, true, true, address(marketManager));
        emit ActionPaused("Transfer Paused", false);

        marketManager.setTransferPaused(false);

        assertEq(marketManager.transferPaused(), 1);
    }
}
