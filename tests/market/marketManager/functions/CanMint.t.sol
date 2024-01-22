// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseMarketManager } from "../TestBaseMarketManager.sol";
import { MarketManager } from "contracts/market/MarketManager.sol";

contract CanMintTest is TestBaseMarketManager {
    function test_canMint_fail_whenMintPaused() public {
        marketManager.listToken(address(dUSDC));

        marketManager.setMintPaused(address(dUSDC), true);
        vm.expectRevert(MarketManager.MarketManager__Paused.selector);
        marketManager.canMint(address(dUSDC));
    }

    function test_canMint_fail_whenTokenNotListed() public {
        vm.expectRevert(MarketManager.MarketManager__TokenNotListed.selector);
        marketManager.canMint(address(dUSDC));
    }

    function test_canMint_success() public {
        marketManager.listToken(address(dUSDC));
        marketManager.canMint(address(dUSDC));
    }
}
