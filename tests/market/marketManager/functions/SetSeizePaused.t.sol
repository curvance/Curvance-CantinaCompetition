// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseMarketManager } from "../TestBaseMarketManager.sol";
import { MarketManager } from "contracts/market/MarketManager.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract SetSeizePausedTest is TestBaseMarketManager {
    event ActionPaused(string action, bool pauseState);

    function test_setSeizePaused_fail_whenCallerIsNotAuthorized() public {
        vm.prank(address(1));

        vm.expectRevert(MarketManager.MarketManager__Unauthorized.selector);
        marketManager.setSeizePaused(true);
    }

    // function test_setSeizePaused_success() public {
    //     vm.expectRevert(MarketManager.MarketManager__TokenNotListed.selector);
    //     marketManager.canSeize(address(cBALRETH), address(dUSDC));

    //     marketManager.listToken(address(cBALRETH));
    //     marketManager.listToken(address(dUSDC));

    //     marketManager.canSeize(address(cBALRETH), address(dUSDC));

    //     assertEq(marketManager.seizePaused(), 1);

    //     vm.expectEmit(true, true, true, true, address(marketManager));
    //     emit ActionPaused("Seize Paused", true);

    //     marketManager.setSeizePaused(true);

    //     vm.expectRevert(MarketManager.MarketManager__Paused.selector);
    //     marketManager.canSeize(address(cBALRETH), address(dUSDC));

    //     assertEq(marketManager.seizePaused(), 2);

    //     vm.expectEmit(true, true, true, true, address(marketManager));
    //     emit ActionPaused("Seize Paused", false);

    //     marketManager.setSeizePaused(false);

    //     assertEq(marketManager.seizePaused(), 1);

    //     MarketManager newMarketManager = new MarketManager(
    //         ICentralRegistry(address(centralRegistry)),
    //         address(gaugePool)
    //     );

    //     centralRegistry.addLendingMarket(address(newMarketManager), 0);
    //     cBALRETH.setMarketManager(address(newMarketManager));

    //     vm.expectRevert(MarketManager.MarketManager__MarketManagerMismatch.selector);
    //     marketManager.canSeize(address(cBALRETH), address(dUSDC));
    // }
}
