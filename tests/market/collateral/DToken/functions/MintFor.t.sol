// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseDToken } from "../TestBaseDToken.sol";
import { GaugeErrors } from "contracts/gauge/GaugeErrors.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";
import { IMToken } from "contracts/interfaces/market/IMToken.sol";

contract DTokenMintForTest is TestBaseDToken {
    event Transfer(address indexed from, address indexed to, uint256 amount);

    function test_dTokenMintFor_fail_whenTransferZeroAmount() public {
        vm.expectRevert(GaugeErrors.InvalidAmount.selector);
        dUSDC.mintFor(0, user1);
    }

    function test_dTokenMintFor_fail_whenMintIsNotAllowed() public {
        lendtroller.setMintPaused(IMToken(address(dUSDC)), true);

        vm.expectRevert(Lendtroller.Lendtroller__Paused.selector);
        dUSDC.mintFor(100e6, user1);
    }

    function test_dTokenMintFor_success() public {
        uint256 underlyingBalance = usdc.balanceOf(address(this));
        uint256 balance = dUSDC.balanceOf(address(this));
        uint256 user1Balance = dUSDC.balanceOf(user1);
        uint256 totalSupply = dUSDC.totalSupply();

        vm.expectEmit(true, true, true, true, address(dUSDC));
        emit Transfer(address(0), user1, 100e6);

        dUSDC.mintFor(100e6, user1);

        assertEq(usdc.balanceOf(address(this)), underlyingBalance - 100e6);
        assertEq(dUSDC.balanceOf(address(this)), balance);
        assertEq(dUSDC.balanceOf(user1), user1Balance + 100e6);
        assertEq(dUSDC.totalSupply(), totalSupply + 100e6);
    }
}
