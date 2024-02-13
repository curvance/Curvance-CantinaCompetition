// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseCTokenCompounding } from "../TestBaseCTokenCompounding.sol";
import { GaugeErrors } from "contracts/gauge/GaugeErrors.sol";
import { MarketManager } from "contracts/market/MarketManager.sol";

contract CTokenCompoundingTransferFromTest is TestBaseCTokenCompounding {
    event Transfer(address indexed from, address indexed to, uint256 amount);

    function test_cTokenCompoundingTransferFrom_fail_whenSenderAndReceiverAreSame()
        public
    {
        vm.expectRevert(GaugeErrors.InvalidAmount.selector);
        cBALRETH.transferFrom(address(this), address(this), 1e18);
    }

    function test_cTokenCompoundingTransferFrom_fail_whenTransferZeroAmount()
        public
    {
        vm.expectRevert(GaugeErrors.InvalidAmount.selector);
        cBALRETH.transferFrom(address(this), user1, 0);
    }

    function test_cTokenCompoundingTransferFrom_fail_whenAllowanceIsInvalid()
        public
    {
        vm.expectRevert();
        cBALRETH.transferFrom(user1, address(this), 100);
    }

    function test_cTokenCompoundingTransferFrom_fail_whenTransferIsNotAllowed()
        public
    {
        marketManager.setTransferPaused(true);

        vm.expectRevert(MarketManager.MarketManager__Paused.selector);
        cBALRETH.transferFrom(address(this), user1, 100);
    }

    function test_cTokenCompoundingTransferFrom_success() public {
        cBALRETH.mint(100, address(this));

        uint256 balance = cBALRETH.balanceOf(address(this));
        uint256 user1Balance = cBALRETH.balanceOf(user1);

        cBALRETH.approve(address(this), 100);

        vm.expectEmit(true, true, true, true, address(cBALRETH));
        emit Transfer(address(this), user1, 100);

        cBALRETH.transferFrom(address(this), user1, 100);

        assertEq(cBALRETH.balanceOf(address(this)), balance - 100);
        assertEq(cBALRETH.balanceOf(user1), user1Balance + 100);
    }
}
