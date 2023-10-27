// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseLendtroller } from "../TestBaseLendtroller.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";
import { IMToken } from "contracts/interfaces/market/IMToken.sol";

contract ExitMarketTest is TestBaseLendtroller {
    address[] public tokens;

    event MarketExited(address mToken, address account);

    function setUp() public override {
        super.setUp();

        tokens.push(address(dUSDC));
        tokens.push(address(dDAI));
        tokens.push(address(cBALRETH));

        for (uint256 i = 0; i < tokens.length; i++) {
            lendtroller.listToken(tokens[i]);
        }
    }

    function test_exitMarket_fail_whenUserHasActiveLoan() public {
        skip(gaugePool.startTime() - block.timestamp);
        chainlinkEthUsd.updateRoundData(0, 1500e8, block.timestamp, block.timestamp);
        chainlinkUsdcUsd.updateRoundData(0, 1e8, block.timestamp, block.timestamp);
        chainlinkUsdcEth.updateRoundData(0, 1500e18, block.timestamp, block.timestamp);
        chainlinkDaiUsd.updateRoundData(0, 1e8, block.timestamp, block.timestamp);
        chainlinkDaiEth.updateRoundData(0, 1500e18, block.timestamp, block.timestamp);

        lendtroller.updateCollateralToken(IMToken(address(cBALRETH)), 2000, 100, 3000, 3000, 7000);

        // Need some CTokens/collateral to have enough liquidity for borrowing
        deal(address(balRETH), user1, 10_000e18);
        deal(address(usdc), address(dUSDC), 10_000e6);
        vm.startPrank(user1);
        lendtroller.enterMarkets(tokens);
        balRETH.approve(address(cBALRETH), 1_000e18);
        cBALRETH.mint(1_000e18);
        vm.stopPrank();

        vm.startPrank(user1);
        dUSDC.borrow(1e6);
        vm.expectRevert(Lendtroller.Lendtroller__HasActiveLoan.selector);
        lendtroller.exitMarket(address(dUSDC));
        vm.stopPrank();
    }

    function test_exitMarket_success_whenUserNotInMarket() public {
        for (uint256 i = 0; i < tokens.length; i++) {
            (bool isListed, , uint256 collateralizationRatio) = lendtroller
                .getMTokenData(tokens[i]);
            assertTrue(isListed);
            assertEq(collateralizationRatio, 0);
            assertFalse(
                lendtroller.getAccountMembership(tokens[i], address(this))
            );

            lendtroller.exitMarket(tokens[i]);

            (isListed, , collateralizationRatio) = lendtroller.getMTokenData(
                tokens[i]
            );
            assertTrue(isListed);
            assertEq(collateralizationRatio, 0);
            assertFalse(
                lendtroller.getAccountMembership(tokens[i], address(this))
            );
        }
    }

    function test_exitMarket_success_whenUserInMarket() public {
        vm.prank(user1);
        lendtroller.enterMarkets(tokens);

        for (uint256 i; i < tokens.length; i++) {
            assertTrue(
                lendtroller.getAccountMembership(tokens[i], user1)
            );            
        }

        vm.prank(user1);
        lendtroller.exitMarket(tokens[0]);

        assertFalse(
            lendtroller.getAccountMembership(tokens[0], user1)
        );

        IMToken[] memory accountAssets = lendtroller.getAccountAssets(user1);
        assertEq(accountAssets.length, 2);

        for (uint256 i; i < accountAssets.length; i++) {
            assertNotEq(tokens[0], address(accountAssets[i]));
        }

        vm.prank(user1);
        lendtroller.exitMarket(tokens[1]);

        assertFalse(
            lendtroller.getAccountMembership(tokens[0], user1)
        );

        accountAssets = lendtroller.getAccountAssets(user1);
        assertEq(accountAssets.length, 1);
        assertNotEq(tokens[0], address(accountAssets[0]));
        assertNotEq(tokens[1], address(accountAssets[0]));
    }
}
