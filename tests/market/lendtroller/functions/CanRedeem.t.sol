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
        lendtroller.notifyBorrow(address(dUSDC), user1);

        vm.expectRevert(Lendtroller.Lendtroller__MinimumHoldPeriod.selector);
        lendtroller.canRedeem(address(dUSDC), user1, 100e6);
    }

    function test_canRedeem_success_whenPastMinimumHoldPeriod() public {
        vm.prank(address(dUSDC));
        lendtroller.notifyBorrow(address(dUSDC), user1);

        skip(20 minutes);
        lendtroller.canRedeem(address(dUSDC), user1, 100e6);
    }

    function test_canRedeem_success_whenRedeemerNotInMarket() public {
        assertFalse(lendtroller.hasPosition(address(dUSDC), user1));
        lendtroller.canRedeem(address(dUSDC), user1, 100e6);
    }

    function test_canRedeem_success_DTokenCanAlwaysBeRedeemed() public {
        assertFalse(dUSDC.isCToken());
        lendtroller.canRedeem(address(dUSDC), user1, 100e6);
    }

    function test_canRedeem_fail_WhenCTokenInsufficientLiquidity() public {
        skip(gaugePool.startTime() - block.timestamp);
        chainlinkEthUsd.updateRoundData(
            0,
            1500e8,
            block.timestamp,
            block.timestamp
        );
        chainlinkUsdcUsd.updateRoundData(
            0,
            1e8,
            block.timestamp,
            block.timestamp
        );
        chainlinkUsdcEth.updateRoundData(
            0,
            1500e18,
            block.timestamp,
            block.timestamp
        );
        lendtroller.listToken(address(cBALRETH));
        lendtroller.updateCollateralToken(
            IMToken(address(cBALRETH)),
            7000,
            3000,
            3000,
            2000,
            2000,
            100,
            1000
        );

        assertTrue(cBALRETH.isCToken());
        deal(address(balRETH), user1, 10_000e18);
        vm.startPrank(user1);
        balRETH.approve(address(cBALRETH), 1_000e18);
        cBALRETH.mint(1e18);
        lendtroller.postCollateral(user1, address(cBALRETH), 9e17);
        vm.stopPrank();

        assertTrue(lendtroller.hasPosition(address(cBALRETH), user1));

        vm.expectRevert(
            Lendtroller.Lendtroller__InsufficientLiquidity.selector
        );
        lendtroller.canRedeem(address(cBALRETH), user1, 100e18);
    }
}
