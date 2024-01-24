// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseMarketManager } from "../TestBaseMarketManager.sol";
import { MarketManager } from "contracts/market/MarketManager.sol";
import { IMToken } from "contracts/interfaces/market/IMToken.sol";

contract CanRedeemTest is TestBaseMarketManager {
    function setUp() public override {
        super.setUp();

        marketManager.listToken(address(dUSDC));
    }

    function test_canRedeem_fail_whenTokenNotListed() public {
        vm.expectRevert(MarketManager.MarketManager__TokenNotListed.selector);
        marketManager.canRedeem(address(cBALRETH), user1, 100e6);
    }

    function test_canRedeem_fail_whenWithinMinimumHoldPeriod() public {
        vm.prank(address(dUSDC));
        marketManager.notifyBorrow(address(dUSDC), user1);

        vm.expectRevert(MarketManager.MarketManager__MinimumHoldPeriod.selector);
        marketManager.canRedeem(address(dUSDC), user1, 100e6);
    }

    function test_canRedeem_success_whenPastMinimumHoldPeriod() public {
        vm.prank(address(dUSDC));
        marketManager.notifyBorrow(address(dUSDC), user1);

        skip(20 minutes);
        marketManager.canRedeem(address(dUSDC), user1, 100e6);
    }

    function test_canRedeem_success_whenRedeemerNotInMarket() public {
        bool hasPosition;
        (hasPosition,,)= marketManager.tokenDataOf(user1, address(dUSDC));

        assertFalse(hasPosition);
        marketManager.canRedeem(address(dUSDC), user1, 100e6);
    }

    function test_canRedeem_success_DTokenCanAlwaysBeRedeemed() public {
        assertFalse(dUSDC.isCToken());
        marketManager.canRedeem(address(dUSDC), user1, 100e6);
    }

    function test_canRedeem_fail_WhenCTokenInsufficientLiquidity() public {
        skip(gaugePool.startTime() - block.timestamp);

        mockWethFeed.setMockUpdatedAt(block.timestamp);
        mockRethFeed.setMockUpdatedAt(block.timestamp);
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
        marketManager.listToken(address(cBALRETH));
        _setCbalRETHCollateralCaps(100_000e18);

        assertTrue(cBALRETH.isCToken());
        deal(address(balRETH), user1, 10_000e18);
        vm.startPrank(user1);
        balRETH.approve(address(cBALRETH), 1_000e18);
        cBALRETH.deposit(1e18, user1);
        marketManager.postCollateral(user1, address(cBALRETH), 9e17);
        vm.stopPrank();

        bool hasPosition;
        (hasPosition,,)= marketManager.tokenDataOf(user1, address(cBALRETH));

        assertTrue(hasPosition);

        skip(20 minutes);
        vm.expectRevert(
            MarketManager.MarketManager__InsufficientCollateral.selector
        );
        marketManager.canRedeem(address(cBALRETH), user1, 100e18);
    }
}
