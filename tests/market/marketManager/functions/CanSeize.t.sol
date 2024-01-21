// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseMarketManager } from "../TestBaseMarketManager.sol";
import { MarketManager } from "contracts/market/MarketManager.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract CanSeizeTest is TestBaseMarketManager {
    function test_canSeize_fail_whenPaused() public {
        marketManager.setSeizePaused(true);

        vm.expectRevert(MarketManager.MarketManager__Paused.selector);
        marketManager.canSeize(address(cBALRETH), address(dUSDC));
    }

    function test_canSeize_fail_whenCTokenNotListed() public {
        vm.expectRevert(MarketManager.MarketManager__TokenNotListed.selector);
        marketManager.canSeize(address(cBALRETH), address(dUSDC));
    }

    function test_canSeize_fail_whenDTokenNotListed() public {
        marketManager.listToken(address(cBALRETH));

        vm.expectRevert(MarketManager.MarketManager__TokenNotListed.selector);
        marketManager.canSeize(address(cBALRETH), address(dUSDC));
    }

    function test_canSeize_success() public {
        marketManager.listToken(address(cBALRETH));
        marketManager.listToken(address(dUSDC));

        marketManager.canSeize(address(cBALRETH), address(dUSDC));
    }

    // function test_canSeize_fail_whenMarketManagersMismatch() public {
    //     marketManager.listToken(address(cBALRETH));
    //     marketManager.listToken(address(dUSDC));

    //     MarketManager newMarketManager = new MarketManager(
    //         ICentralRegistry(address(centralRegistry)),
    //         address(gaugePool)
    //     );
    //     centralRegistry.addLendingMarket(address(newMarketManager), 1000);
    //     dUSDC.setMarketManager(address(newMarketManager));

    //     vm.expectRevert(MarketManager.MarketManager__MarketManagerMismatch.selector);
    //     marketManager.canSeize(address(cBALRETH), address(dUSDC));
    // }
}
