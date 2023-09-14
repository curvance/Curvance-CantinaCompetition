// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseCToken } from "../TestBaseCToken.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";
import { IMToken } from "contracts/interfaces/market/IMToken.sol";

contract CTokenMintTest is TestBaseCToken {
    event Transfer(address indexed from, address indexed to, uint256 amount);

    function test_cTokenMint_fail_whenTransferZeroAmount() public {
        vm.expectRevert("BasePositionVault: ZERO_SHARES");
        cBALRETH.mint(0);
    }

    function test_cTokenMint_fail_whenMintIsNotAllowed() public {
        lendtroller.setMintPaused(IMToken(address(cBALRETH)), true);

        vm.expectRevert(Lendtroller.Lendtroller__Paused.selector);
        cBALRETH.mint(100);
    }

    function test_cTokenMint_success() public {
        uint256 underlyingBalance = balRETH.balanceOf(address(this));
        uint256 balance = cBALRETH.balanceOf(address(this));
        uint256 totalSupply = cBALRETH.totalSupply();

        vm.expectEmit(true, true, true, address(cBALRETH));
        emit Transfer(address(cBALRETH), address(this), 100);

        cBALRETH.mint(100);

        assertEq(balRETH.balanceOf(address(this)), underlyingBalance - 100);
        assertEq(cBALRETH.balanceOf(address(this)), balance + 100);
        assertEq(cBALRETH.totalSupply(), totalSupply + 100);
    }
}
