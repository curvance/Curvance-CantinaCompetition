// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseMarketManager } from "../TestBaseMarketManager.sol";
import { MarketManager } from "contracts/market/MarketManager.sol";

contract NotifyBorrowTest is TestBaseMarketManager {
    event MarketEntered(address mToken, address account);

    function setUp() public override {
        super.setUp();

        marketManager.listToken(address(dUSDC));
    }

    function test_notifyBorrow_fail_whenCallerIsNotMToken() public {
        vm.expectRevert(MarketManager.MarketManager__Unauthorized.selector);
        marketManager.notifyBorrow(address(dUSDC), user1);
    }

    function test_notifyBorrow_success() public {
        vm.prank(address(dUSDC));
        marketManager.notifyBorrow(address(dUSDC), user1);

        assertEq(marketManager.accountAssets(user1), block.timestamp);
    }
}
