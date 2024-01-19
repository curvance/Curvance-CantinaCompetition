// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseDToken } from "../TestBaseDToken.sol";
import { GaugeErrors } from "contracts/gauge/GaugeErrors.sol";
import { MarketManager } from "contracts/market/MarketManager.sol";

contract DTokenMintTest is TestBaseDToken {
    event Transfer(address indexed from, address indexed to, uint256 amount);

    function test_dTokenMint_fail_whenTransferZeroAmount() public {
        vm.expectRevert(GaugeErrors.InvalidAmount.selector);
        dUSDC.mint(0);
    }

    function test_dTokenMint_fail_whenMintIsNotAllowed() public {
        marketManager.setMintPaused(address(dUSDC), true);

        vm.expectRevert(MarketManager.MarketManager__Paused.selector);
        dUSDC.mint(100e6);
    }

    function test_dTokenMint_success() public {
        uint256 underlyingBalance = usdc.balanceOf(address(this));
        uint256 balance = dUSDC.balanceOf(address(this));
        uint256 totalSupply = dUSDC.totalSupply();

        vm.expectEmit(true, true, true, true, address(dUSDC));
        emit Transfer(address(0), address(this), 100e6);

        dUSDC.mint(100e6);

        assertEq(usdc.balanceOf(address(this)), underlyingBalance - 100e6);
        assertEq(dUSDC.balanceOf(address(this)), balance + 100e6);
        assertEq(dUSDC.totalSupply(), totalSupply + 100e6);
    }
}
