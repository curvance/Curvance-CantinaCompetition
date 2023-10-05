// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseCToken } from "../TestBaseCToken.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";
import { IMToken } from "contracts/interfaces/market/IMToken.sol";

contract CTokenMintForTest is TestBaseCToken {
    event Transfer(address indexed from, address indexed to, uint256 amount);

    function test_cTokenMintFor_fail_whenTransferZeroAmount() public {
        vm.expectRevert("BasePositionVault: ZERO_SHARES");
        cBALRETH.mintFor(0, user1);
    }

    function test_cTokenMintFor_fail_whenMintIsNotAllowed() public {
        lendtroller.setMintPaused(IMToken(address(cBALRETH)), true);

        vm.expectRevert(Lendtroller.Lendtroller__Paused.selector);
        cBALRETH.mintFor(100, user1);
    }

    function test_cTokenMintFor_success() public {
        uint256 underlyingBalance = balRETH.balanceOf(address(this));
        uint256 balance = cBALRETH.balanceOf(address(this));
        uint256 user1Balance = cBALRETH.balanceOf(user1);
        uint256 totalSupply = cBALRETH.totalSupply();

        vm.expectEmit(true, true, true, true, address(cBALRETH));
        emit Transfer(address(0), user1, 100);

        cBALRETH.mintFor(100, user1);

        assertEq(balRETH.balanceOf(address(this)), underlyingBalance - 100);
        assertEq(cBALRETH.balanceOf(address(this)), balance);
        assertEq(cBALRETH.balanceOf(user1), user1Balance + 100);
        assertEq(cBALRETH.totalSupply(), totalSupply + 100);
    }
}
