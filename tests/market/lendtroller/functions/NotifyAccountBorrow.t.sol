// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseLendtroller } from "../TestBaseLendtroller.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";

contract NotifyAccountBorrowTest is TestBaseLendtroller {
    event MarketEntered(address mToken, address account);

    function setUp() public override {
        super.setUp();

        lendtroller.listMarketToken(address(dUSDC), 200);
    }

    function test_notifyAccountBorrow_fail_whenCallerIsNotMToken() public {
        vm.expectRevert(Lendtroller.Lendtroller__TokenNotListed.selector);
        lendtroller.notifyAccountBorrow(user1);
    }

    function test_notifyAccountBorrow_fail_whenCallerMTokenIsNotListed()
        public
    {
        vm.prank(address(dDAI));

        vm.expectRevert(Lendtroller.Lendtroller__TokenNotListed.selector);
        lendtroller.notifyAccountBorrow(user1);
    }

    function test_notifyAccountBorrow_success() public {
        vm.prank(address(dUSDC));
        lendtroller.notifyAccountBorrow(user1);

        assertEq(lendtroller.accountAssets(user1), block.timestamp);
    }
}
