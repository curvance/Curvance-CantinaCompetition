// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseMarketManager } from "../TestBaseMarketManager.sol";
import { MarketManager } from "contracts/market/MarketManager.sol";
import { IMToken, AccountSnapshot } from "contracts/interfaces/market/IMToken.sol";

contract CanRepayTest is TestBaseMarketManager {
    function test_canRepay_fail_whenTokenNotListed() public {
        vm.expectRevert(MarketManager.MarketManager__TokenNotListed.selector);
        marketManager.canRepay(address(dUSDC), user1);
    }

    function test_canRepay_fail_withinMinimumHoldPeriod() public {
        marketManager.listToken(address(dUSDC));
        vm.prank(address(dUSDC));
        marketManager.notifyBorrow(address(dUSDC), user1);

        vm.expectRevert(MarketManager.MarketManager__MinimumHoldPeriod.selector);
        marketManager.canRepay(address(dUSDC), user1);
    }

    function test_canRepay_success_whenPastMinimumHoldPeriod() public {
        marketManager.listToken(address(dUSDC));
        vm.prank(address(dUSDC));
        marketManager.notifyBorrow(address(dUSDC), user1);

        skip(20 minutes);
        marketManager.canRepay(address(dUSDC), user1);
    }

    function test_canRepay_success() public {
        marketManager.listToken(address(dUSDC));
        marketManager.canRepay(address(dUSDC), user1);
    }
}
