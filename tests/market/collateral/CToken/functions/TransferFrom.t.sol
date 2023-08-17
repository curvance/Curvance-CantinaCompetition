// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseCToken } from "../TestBaseCToken.sol";
import { GaugeErrors } from "contracts/gauge/GaugeErrors.sol";
import { CToken } from "contracts/market/collateral/CToken.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";

contract CTokenTransferFromTest is TestBaseCToken {
    event Transfer(address indexed from, address indexed to, uint256 amount);

    function test_cTokenTransferFrom_fail_whenSenderAndReceiverAreSame()
        public
    {
        vm.expectRevert(CToken.CToken__TransferNotAllowed.selector);
        cBALRETH.transferFrom(address(this), address(this), 1e18);
    }

    function test_cTokenTransferFrom_fail_whenTransferZeroAmount() public {
        vm.expectRevert(GaugeErrors.InvalidAmount.selector);
        cBALRETH.transferFrom(address(this), user1, 0);
    }

    function test_cTokenTransferFrom_fail_whenAllowanceIsInvalid() public {
        vm.expectRevert();
        cBALRETH.transferFrom(user1, address(this), 100);
    }

    function test_transfer_fail_whenTransferIsNotAllowed() public {
        lendtroller.setTransferPaused(true);

        vm.expectRevert(Lendtroller.Lendtroller_Paused.selector);
        cBALRETH.transferFrom(address(this), user1, 100);
    }

    function test_cTokenTransferFrom_success() public {
        uint256 balance = cBALRETH.balanceOf(address(this));
        uint256 user1Balance = cBALRETH.balanceOf(user1);

        vm.expectEmit(true, true, true, true, address(cBALRETH));
        emit Transfer(address(this), user1, 100);

        cBALRETH.transferFrom(address(this), user1, 100);

        assertEq(cBALRETH.balanceOf(address(this)), balance - 100);
        assertEq(cBALRETH.balanceOf(user1), user1Balance + 100);
    }
}
