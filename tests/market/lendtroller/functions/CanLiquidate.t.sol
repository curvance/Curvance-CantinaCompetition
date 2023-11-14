// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseLendtroller } from "../TestBaseLendtroller.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";
import { PriceRouter } from "contracts/oracles/PriceRouter.sol";
import { PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";
import { WAD } from "contracts/libraries/Constants.sol";
import { IMToken } from "contracts/interfaces/market/IMToken.sol";

contract CanLiquidateTest is TestBaseLendtroller {
    function test_canLiquidate_fail_whenDTokenNotListed() public {
        vm.expectRevert(Lendtroller.Lendtroller__TokenNotListed.selector);
        lendtroller.canLiquidate(
            address(dUSDC),
            address(cBALRETH),
            user1,
            1000,
            false
        );
    }

    function test_canLiquidate_fail_whenCTokenNotListed() public {
        lendtroller.listToken(address(dUSDC));
        vm.expectRevert(Lendtroller.Lendtroller__TokenNotListed.selector);
        lendtroller.canLiquidate(
            address(dUSDC),
            address(cBALRETH),
            user1,
            1000,
            false
        );
    }

    function test_canLiquidate_fail_whenCollRatioZero() public {
        lendtroller.listToken(address(dUSDC));
        lendtroller.listToken(address(cBALRETH));

        vm.expectRevert(Lendtroller.Lendtroller__InvalidParameter.selector);
        lendtroller.canLiquidate(
            address(dUSDC),
            address(cBALRETH),
            user1,
            1000,
            false
        );
    }

    function test_canLiquidate_fail_whenUserHasNotEnteredAnyMarket() public {
        lendtroller.listToken(address(dUSDC));
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

        vm.expectRevert(PriceRouter.PriceRouter__InvalidParameter.selector);
        lendtroller.canLiquidate(
            address(dUSDC),
            address(cBALRETH),
            user1,
            1000,
            false
        );
    }

    function test_canLiquidate_fail_whenAccountHasNoBorrowsAndCollateralPosted()
        public
    {
        lendtroller.listToken(address(dUSDC));
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

        vm.expectRevert(PriceRouter.PriceRouter__InvalidParameter.selector);
        lendtroller.canLiquidate(
            address(dUSDC),
            address(cBALRETH),
            user1,
            1000,
            false
        );
    }

    function test_canLiquidate_fail_whenShortfallInsufficient() public {
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
        lendtroller.listToken(address(dUSDC));
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
        address[] memory tokens = new address[](1);
        tokens[0] = address(cBALRETH);
        uint256[] memory caps = new uint256[](1);
        caps[0] = 100_000e18;
        lendtroller.setCTokenCollateralCaps(tokens, caps);

        deal(address(balRETH), user1, 10_000e18);
        vm.startPrank(user1);
        balRETH.approve(address(cBALRETH), 1_000e18);
        cBALRETH.mint(1_000e18);
        lendtroller.postCollateral(user1, address(cBALRETH), 999e18);
        vm.stopPrank();

        vm.expectRevert(
            Lendtroller.Lendtroller__NoLiquidationAvailable.selector
        );
        lendtroller.canLiquidate(
            address(dUSDC),
            address(cBALRETH),
            user1,
            1000,
            false
        );
    }

    function test_canLiquidate_success() public {
        lendtroller.listToken(address(dUSDC));
        lendtroller.listToken(address(cBALRETH));
        lendtroller.updateCollateralToken(
            IMToken(address(cBALRETH)),
            7000, // 70% collateral ratio
            3000,
            3000,
            2000,
            2000,
            100,
            1000
        );
        address[] memory tokens = new address[](1);
        tokens[0] = address(cBALRETH);
        uint256[] memory caps = new uint256[](1);
        caps[0] = 100_000e18;
        lendtroller.setCTokenCollateralCaps(tokens, caps);

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
        lendtroller.postCollateral(user1, address(cBALRETH), 1e18 - 1);

        // Borrow dUSDC with cBALRETH as collateral
        deal(_USDC_ADDRESS, address(dUSDC), 100_000e6);
        dUSDC.borrow(1000e6);
        vm.stopPrank();

        assertEq(usdc.balanceOf(user1), 1000e6);

        // Can not liquidate yet while collateral is above required collateral ratio
        vm.expectRevert(
            Lendtroller.Lendtroller__NoLiquidationAvailable.selector
        );
        lendtroller.canLiquidate(
            address(dUSDC),
            address(cBALRETH),
            user1,
            1000e6,
            false
        );

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
        ) = lendtroller.canLiquidate(
                address(dUSDC),
                address(cBALRETH),
                user1,
                1000e6,
                false
            );

        (, , , , , , , uint256 baseCFactor, uint256 cFactorCurve) = lendtroller
            .tokenData(address(cBALRETH));
        uint256 cFactor = baseCFactor + ((cFactorCurve * 1) / WAD);
        uint256 expectedLiqAmount = (cFactor *
            dUSDC.debtBalanceStored(user1)) / WAD;

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

        (, , , , uint256 liqBaseIncentive, , , , ) = lendtroller.tokenData(
            address(cBALRETH)
        );
        uint256 debtTokenPrice = 1e18; // USDC price
        uint256 debtToCollateralRatio = (liqBaseIncentive *
            debtTokenPrice *
            WAD) / (data.price * cBALRETH.exchangeRateStored());

        uint256 amountAdjusted = (liqAmount * (10 ** cBALRETH.decimals())) /
            (10 ** dUSDC.decimals());

        uint256 expectedLiquidatedTokens = (amountAdjusted *
            debtToCollateralRatio) / WAD;

        assertEq(
            liquidatedTokens,
            expectedLiquidatedTokens,
            "canLiquidate() returns the amount of CTokens to be seized in liquidation"
        );

        uint256 liqFee = (WAD * (100 * 1e14)) / liqBaseIncentive;
        uint256 expectedProtocolTokens = (expectedLiquidatedTokens * liqFee) /
            WAD;

        assertEq(
            protocolTokens,
            expectedProtocolTokens,
            "canLiquidate() returns the amount of CTokens to be seized for the protocol"
        );

        assertGt(liquidatedTokens, protocolTokens);
    }
}
