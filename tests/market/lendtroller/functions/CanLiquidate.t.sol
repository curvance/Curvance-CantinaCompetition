// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseLendtroller } from "../TestBaseLendtroller.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";
import { PriceRouter } from "contracts/oracles/PriceRouter.sol";
import { PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";
import { EXP_SCALE } from "contracts/libraries/Constants.sol";
import { IMToken } from "contracts/interfaces/market/IMToken.sol";

contract CanLiquidateTest is TestBaseLendtroller {
    function test_canLiquidate_fail_whenDTokenNotListed() public {
        vm.expectRevert(Lendtroller.Lendtroller__TokenNotListed.selector);
        lendtroller.canLiquidate(address(dUSDC), address(cBALRETH), user1);
    }

    function test_canLiquidate_fail_whenCTokenNotListed() public {
        lendtroller.listMarketToken(address(dUSDC));
        vm.expectRevert(Lendtroller.Lendtroller__TokenNotListed.selector);
        lendtroller.canLiquidate(address(dUSDC), address(cBALRETH), user1);
    }

    function test_canLiquidate_fail_whenCollRatioZero() public {
        lendtroller.listMarketToken(address(dUSDC));
        lendtroller.listMarketToken(address(cBALRETH));

        vm.expectRevert(Lendtroller.Lendtroller__InvalidParameter.selector);
        lendtroller.canLiquidate(address(dUSDC), address(cBALRETH), user1);
    }

    function test_canLiquidate_fail_whenUserHasNotEnteredAnyMarket() public {
        lendtroller.listMarketToken(address(dUSDC));
        lendtroller.listMarketToken(address(cBALRETH));
        lendtroller.updateCollateralToken(
            IMToken(address(cBALRETH)),
            2000,
            100,
            3000,
            3000,
            7000
        );

        vm.expectRevert(PriceRouter.PriceRouter__InvalidParameter.selector);
        lendtroller.canLiquidate(address(dUSDC), address(cBALRETH), user1);
    }

    function test_canLiquidate_fail_whenShortfallInsufficient() public {
        lendtroller.listMarketToken(address(dUSDC));
        lendtroller.listMarketToken(address(cBALRETH));
        lendtroller.updateCollateralToken(
            IMToken(address(cBALRETH)),
            2000,
            100,
            3000,
            3000,
            7000
        );
        address[] memory markets = new address[](1);
        markets[0] = address(dUSDC);
        vm.prank(user1);
        lendtroller.enterMarkets(markets);

        vm.expectRevert(
            Lendtroller.Lendtroller__InsufficientShortfall.selector
        );
        lendtroller.canLiquidate(address(dUSDC), address(cBALRETH), user1);
    }

    function test_canLiquidate_fail_whenT() public {
        lendtroller.listMarketToken(address(dUSDC));
        lendtroller.listMarketToken(address(cBALRETH));
        lendtroller.updateCollateralToken(
            IMToken(address(cBALRETH)),
            2000,
            100,
            3000,
            3000,
            7000 // 70% collateral ratio
        );
        address[] memory markets = new address[](2);
        markets[0] = address(dUSDC);
        markets[1] = address(cBALRETH);
        vm.prank(user1);
        lendtroller.enterMarkets(markets);

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

        // Mint cBALRETH for collateral
        deal(address(balRETH), user1, 10_000e18);
        vm.startPrank(user1);
        balRETH.approve(address(cBALRETH), 1_000e18);
        cBALRETH.mint(1e18);

        // Borrow dUSDC with cBALRETH as collateral
        deal(_USDC_ADDRESS, address(dUSDC), 100_000e6);
        dUSDC.borrow(1000e6);
        vm.stopPrank();

        assertEq(usdc.balanceOf(user1), 1000e6);

        // Can not liquidate yet while collateral is above required collateral ratio
        vm.expectRevert(
            Lendtroller.Lendtroller__InsufficientShortfall.selector
        );
        lendtroller.canLiquidate(address(dUSDC), address(cBALRETH), user1);

        // Price of ETH drops and balRETH collateral goes below required collateral ratio
        // and can now liquidate
        chainlinkEthUsd.updateRoundData(
            0,
            1000e8,
            block.timestamp,
            block.timestamp
        );

        // =================== RESULTS ==================
        (
            uint256 liqAmount,
            uint256 liquidatedTokens,
            uint256 protocolTokens
        ) = lendtroller.canLiquidate(address(dUSDC), address(cBALRETH), user1);

        uint256 expectedLiqAmount = (lendtroller.closeFactor() *
            dUSDC.debtBalanceStored(user1)) / EXP_SCALE;

        assertEq(
            liqAmount,
            expectedLiqAmount,
            "canLiquidate() returns the max liquidation amount based on close factor"
        );

        PriceReturnData memory data = balRETHAdapter.getPrice(
            _BALANCER_WETH_RETH,
            true,
            true
        );

        (, uint256 liqInc, ) = lendtroller.getMTokenData(address(cBALRETH));
        uint256 debtTokenPrice = 1e18; // USDC price
        uint256 debtToCollateralRatio = (liqInc * debtTokenPrice * EXP_SCALE) /
            (data.price * cBALRETH.exchangeRateStored());

        uint256 amountAdjusted = (liqAmount * (10 ** cBALRETH.decimals())) /
            (10 ** dUSDC.decimals());

        uint256 expectedLiquidatedTokens = (amountAdjusted *
            debtToCollateralRatio) / EXP_SCALE;

        assertEq(
            liquidatedTokens,
            expectedLiquidatedTokens,
            "canLiquidate() returns the amount of CTokens to be seized in liquidation"
        );

        uint256 liqFee = (EXP_SCALE * (100 * 1e14)) / liqInc;
        uint256 expectedProtocolTokens = (expectedLiquidatedTokens * liqFee) /
            EXP_SCALE;

        assertEq(
            protocolTokens,
            expectedProtocolTokens,
            "canLiquidate() returns the amount of CTokens to be seized for the protocol"
        );

        assertGt(liquidatedTokens, protocolTokens);
    }
}
