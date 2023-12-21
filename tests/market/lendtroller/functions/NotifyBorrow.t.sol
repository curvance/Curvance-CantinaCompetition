// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseLendtroller } from "../TestBaseLendtroller.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";

contract NotifyBorrowTest is TestBaseLendtroller {
    event MarketEntered(address mToken, address account);

    function setUp() public override {
        super.setUp();

        lendtroller.listToken(address(dUSDC));
    }

    function test_notifyBorrow_fail_whenCallerIsNotMToken() public {
        vm.expectRevert(Lendtroller.Lendtroller__Unauthorized.selector);
        lendtroller.notifyBorrow(address(dUSDC), user1);
    }

    function test_notifyBorrow_success() public {
        vm.prank(address(dUSDC));
        lendtroller.notifyBorrow(address(dUSDC), user1);

        assertEq(lendtroller.accountAssets(user1), block.timestamp);
    }
}
