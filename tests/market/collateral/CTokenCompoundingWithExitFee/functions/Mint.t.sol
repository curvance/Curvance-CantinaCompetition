// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseCTokenCompoundingWithExitFee } from "../TestBaseCTokenCompoundingWithExitFee.sol";
import { MarketManager } from "contracts/market/MarketManager.sol";
import { CTokenCompounding } from "contracts/market/collateral/CTokenCompounding.sol";

contract cTokenCompoundingWithExitFeeMintTest is
    TestBaseCTokenCompoundingWithExitFee
{
    event Transfer(address indexed from, address indexed to, uint256 amount);

    function test_cTokenCompoundingWithExitFeeMint_fail_whenTransferZeroAmount()
        public
    {
        vm.expectRevert(
            CTokenCompounding.CTokenCompounding__ZeroShares.selector
        );
        cBALRETHWithExitFee.mint(0, address(this));
    }

    function test_cTokenCompoundingWithExitFeeMint_fail_whenMintIsNotAllowed()
        public
    {
        marketManager.setMintPaused(address(cBALRETHWithExitFee), true);

        vm.expectRevert(MarketManager.MarketManager__Paused.selector);
        cBALRETHWithExitFee.mint(100, address(this));
    }

    function test_cTokenCompoundingWithExitFeeMint_success() public {
        uint256 underlyingBalance = balRETH.balanceOf(address(this));
        uint256 balance = cBALRETHWithExitFee.balanceOf(address(this));
        uint256 totalSupply = cBALRETHWithExitFee.totalSupply();

        vm.expectEmit(true, true, true, true, address(cBALRETHWithExitFee));
        emit Transfer(address(0), address(this), 100);

        cBALRETHWithExitFee.mint(100, address(this));

        assertEq(balRETH.balanceOf(address(this)), underlyingBalance - 100);
        assertEq(cBALRETHWithExitFee.balanceOf(address(this)), balance + 100);
        assertEq(cBALRETHWithExitFee.totalSupply(), totalSupply + 100);
    }
}
