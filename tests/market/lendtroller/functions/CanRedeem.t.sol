// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseLendtroller } from "../TestBaseLendtroller.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";
import { IMToken } from "contracts/interfaces/market/IMToken.sol";

contract CanRedeemTest is TestBaseLendtroller {
    function setUp() public override {
        super.setUp();

        lendtroller.listToken(address(dUSDC));
    }

    function test_canRedeem_fail_whenTokenNotListed() public {
        vm.expectRevert(Lendtroller.Lendtroller__TokenNotListed.selector);
        lendtroller.canRedeem(address(cBALRETH), user1, 100e6);
    }

    function test_canRedeem_fail_whenWithinMinimumHoldPeriod() public {
        vm.prank(address(dUSDC));
        lendtroller.notifyBorrow(user1);

        vm.expectRevert(Lendtroller.Lendtroller__MinimumHoldPeriod.selector);
        lendtroller.canRedeem(address(dUSDC), user1, 100e6);
    }

    function test_canRedeem_success_whenPastMinimumHoldPeriod() public {
        vm.prank(address(dUSDC));
        lendtroller.notifyBorrow(user1);

        skip(15 minutes);
        lendtroller.canRedeem(address(dUSDC), user1, 100e6);
    }

    function test_canRedeem_success_whenRedeemerNotInMarket() public {
        assertFalse(lendtroller.hasPosition(address(dUSDC), user1));

        lendtroller.canRedeem(address(dUSDC), user1, 100e6);
    }

    function test_canRedeem_success_DTokenCanAlwaysBeRedeemed() public {
        assertFalse(dUSDC.isCToken());
        assertTrue(lendtroller.hasPosition(address(dUSDC), user1));
        lendtroller.canRedeem(address(dUSDC), user1, 100e6);
    }

    function test_canRedeem_fail_WhenCTokenInsufficientLiquidity() public {
        lendtroller.listToken(address(cBALRETH));
        lendtroller.updateCollateralToken(
            IMToken(address(cBALRETH)),
            2000,
            100,
            3000,
            3000,
            7000
        );

        assertTrue(cBALRETH.isCToken());
        assertTrue(lendtroller.hasPosition(address(cBALRETH), user1));
        vm.expectRevert(
            Lendtroller.Lendtroller__InsufficientLiquidity.selector
        );
        lendtroller.canRedeem(address(cBALRETH), user1, 100e6);
    }
}
