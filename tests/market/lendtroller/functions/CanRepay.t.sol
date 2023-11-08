// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseLendtroller } from "../TestBaseLendtroller.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";
import { IMToken, AccountSnapshot } from "contracts/interfaces/market/IMToken.sol";

contract CanRepayTest is TestBaseLendtroller {
    function test_canRepay_fail_whenTokenNotListed() public {
        vm.expectRevert(Lendtroller.Lendtroller__TokenNotListed.selector);
        lendtroller.canRepay(address(dUSDC), user1);
    }

    function test_canRepay_fail_withinMinimumHoldPeriod() public {
        lendtroller.listMarketToken(address(dUSDC));
        lendtroller.notifyBorrow(user1);

        vm.expectRevert(Lendtroller.Lendtroller__MinimumHoldPeriod.selector);
        lendtroller.canRepay(address(dUSDC), user1);
    }

    function test_canRepay_success_whenPastMinimumHoldPeriod() public {
        lendtroller.listMarketToken(address(dUSDC));
        vm.prank(address(dUSDC));
        lendtroller.notifyBorrow(user1);

        skip(15 minutes);
        lendtroller.canRepay(address(dUSDC), user1);
    }

    function test_canRepay_success() public {
        lendtroller.listMarketToken(address(dUSDC));
        lendtroller.canRepay(address(dUSDC), user1);
    }
}
