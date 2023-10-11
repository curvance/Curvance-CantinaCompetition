// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseCToken } from "../TestBaseCToken.sol";
import { GaugeErrors } from "contracts/gauge/GaugeErrors.sol";
import { CToken } from "contracts/market/collateral/CToken.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";

contract CTokenTransferTest is TestBaseCToken {
    event Transfer(address indexed from, address indexed to, uint256 amount);

    function test_cTokenTransfer_fail_whenSenderAndReceiverAreSame() public {
        vm.expectRevert(CToken.CToken__TransferError.selector);
        cBALRETH.transfer(address(this), 100);
    }

    function test_cTokenTransfer_fail_whenTransferZeroAmount() public {
        vm.expectRevert(GaugeErrors.InvalidAmount.selector);
        cBALRETH.transfer(user1, 0);
    }

    function test_cTokenTransfer_fail_whenTransferIsNotAllowed() public {
        lendtroller.setTransferPaused(true);

        vm.expectRevert(Lendtroller.Lendtroller__Paused.selector);
        cBALRETH.transfer(user1, 0);
    }

    function test_cTokenTransfer_success() public {
        uint256 balance = cBALRETH.balanceOf(address(this));
        uint256 user1Balance = cBALRETH.balanceOf(user1);

        vm.expectEmit(true, true, true, true, address(cBALRETH));
        emit Transfer(address(this), user1, 100);

        cBALRETH.transfer(user1, 100);

        assertEq(cBALRETH.balanceOf(address(this)), balance - 100);
        assertEq(cBALRETH.balanceOf(user1), user1Balance + 100);
    }
}
