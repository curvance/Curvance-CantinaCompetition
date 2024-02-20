// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseCTokenCompoundingWithExitFee } from "../TestBaseCTokenCompoundingWithExitFee.sol";
import { GaugeErrors } from "contracts/gauge/GaugeErrors.sol";
import { MarketManager } from "contracts/market/MarketManager.sol";

contract CTokenCompoundingWithExitFeeTransferFromTest is
    TestBaseCTokenCompoundingWithExitFee
{
    event Transfer(address indexed from, address indexed to, uint256 amount);

    function test_cTokenCompoundingWithExitFeeTransferFrom_fail_whenSenderAndReceiverAreSame()
        public
    {
        vm.expectRevert(GaugeErrors.InvalidAmount.selector);
        cBALRETHWithExitFee.transferFrom(address(this), address(this), 1e18);
    }

    function test_cTokenCompoundingWithExitFeeTransferFrom_fail_whenTransferZeroAmount()
        public
    {
        vm.expectRevert(GaugeErrors.InvalidAmount.selector);
        cBALRETHWithExitFee.transferFrom(address(this), user1, 0);
    }

    function test_cTokenCompoundingWithExitFeeTransferFrom_fail_whenAllowanceIsInvalid()
        public
    {
        vm.expectRevert();
        cBALRETHWithExitFee.transferFrom(user1, address(this), 100);
    }

    function test_cTokenCompoundingWithExitFeeTransferFrom_fail_whenTransferIsNotAllowed()
        public
    {
        marketManager.setTransferPaused(true);

        vm.expectRevert(MarketManager.MarketManager__Paused.selector);
        cBALRETHWithExitFee.transferFrom(address(this), user1, 100);
    }

    function test_cTokenCompoundingWithExitFeeTransferFrom_success() public {
        cBALRETHWithExitFee.mint(100, address(this));

        uint256 balance = cBALRETHWithExitFee.balanceOf(address(this));
        uint256 user1Balance = cBALRETHWithExitFee.balanceOf(user1);

        cBALRETHWithExitFee.approve(address(this), 100);

        vm.expectEmit(true, true, true, true, address(cBALRETHWithExitFee));
        emit Transfer(address(this), user1, 100);

        cBALRETHWithExitFee.transferFrom(address(this), user1, 100);

        assertEq(cBALRETHWithExitFee.balanceOf(address(this)), balance - 100);
        assertEq(cBALRETHWithExitFee.balanceOf(user1), user1Balance + 100);
    }
}
