// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { IMToken, AccountSnapshot } from "contracts/interfaces/market/IMToken.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IPendlePTOracle } from "contracts/interfaces/external/pendle/IPendlePtOracle.sol";
import { IPMarket } from "contracts/interfaces/external/pendle/IPMarket.sol";
import { MockDataFeed } from "contracts/mocks/MockDataFeed.sol";

import { CTokenPrimitive, IERC20 } from "contracts/market/collateral/CTokenPrimitive.sol";
import { PendlePrincipalTokenAdaptor } from "contracts/oracles/adaptors/pendle/PendlePrincipalTokenAdaptor.sol";

import "tests/market/TestBaseMarket.sol";

contract User {}

contract TestCTokenForPendlePT is TestBaseMarket {
    address public owner;

    receive() external payable {}

    fallback() external payable {}

    address internal constant _PT_ORACLE =
        0x14030836AEc15B2ad48bB097bd57032559339c92;

    address private _STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address private _PT_STETH = 0x7758896b6AC966BbABcf143eFA963030f17D3EdF; // PT-stETH-26DEC24
    address private _LP_STETH = 0xD0354D4e7bCf345fB117cabe41aCaDb724eccCa2; // PT-stETH-26DEC24/SY-stETH Market

    PendlePrincipalTokenAdaptor adapter;

    MockDataFeed public mockUsdcFeed;
    MockDataFeed public mockWethFeed;
    MockDataFeed public mockStethFeed;

    CTokenPrimitive cPendlePT;
    IERC20 pendlePT = IERC20(_PT_STETH);

    function setUp() public override {
        super.setUp();

        owner = address(this);

        // use mock pricing for testing
        mockUsdcFeed = new MockDataFeed(_CHAINLINK_USDC_USD);
        chainlinkAdaptor.addAsset(_USDC_ADDRESS, address(mockUsdcFeed), true);
        dualChainlinkAdaptor.addAsset(
            _USDC_ADDRESS,
            address(mockUsdcFeed),
            true
        );
        mockWethFeed = new MockDataFeed(_CHAINLINK_ETH_USD);
        chainlinkAdaptor.addAsset(_WETH_ADDRESS, address(mockWethFeed), true);
        dualChainlinkAdaptor.addAsset(
            _WETH_ADDRESS,
            address(mockWethFeed),
            true
        );
        mockStethFeed = new MockDataFeed(_CHAINLINK_ETH_USD);
        chainlinkAdaptor.addAsset(_STETH, address(mockStethFeed), true);
        dualChainlinkAdaptor.addAsset(_STETH, address(mockStethFeed), true);

        priceRouter.addAssetPriceFeed(_STETH, address(chainlinkAdaptor));
        priceRouter.addAssetPriceFeed(_STETH, address(dualChainlinkAdaptor));

        adapter = new PendlePrincipalTokenAdaptor(
            ICentralRegistry(address(centralRegistry)),
            IPendlePTOracle(_PT_ORACLE)
        );
        PendlePrincipalTokenAdaptor.AdaptorData memory adapterData;
        adapterData.market = IPMarket(_LP_STETH);
        adapterData.twapDuration = 12;
        adapterData.quoteAsset = _STETH;
        adapterData.quoteAssetDecimals = 18;
        adapter.addAsset(_PT_STETH, adapterData);

        priceRouter.addApprovedAdaptor(address(adapter));
        priceRouter.addAssetPriceFeed(_PT_STETH, address(adapter));

        // start epoch
        gaugePool.start(address(lendtroller));
        vm.warp(gaugePool.startTime());
        vm.roll(block.number + 1000);

        mockUsdcFeed.setMockUpdatedAt(block.timestamp);
        mockWethFeed.setMockUpdatedAt(block.timestamp);
        mockStethFeed.setMockUpdatedAt(block.timestamp);

        // deploy dUSDC
        {
            _deployDUSDC();
            // support market
            _prepareUSDC(owner, 200000e6);
            usdc.approve(address(dUSDC), 200000e6);
            lendtroller.listToken(address(dUSDC));
            // add MToken support on price router
            priceRouter.addMTokenSupport(address(dUSDC));
            address[] memory markets = new address[](1);
            markets[0] = address(dUSDC);
            // vm.prank(user1);
            // lendtroller.enterMarkets(markets);
            // vm.prank(user2);
            // lendtroller.enterMarkets(markets);
        }

        // deploy cPendlePT
        {
            // deploy aura position vault
            cPendlePT = new CTokenPrimitive(
                ICentralRegistry(address(centralRegistry)),
                pendlePT,
                address(lendtroller)
            );

            // support market
            _preparePT(owner, 1 ether);
            pendlePT.approve(address(cPendlePT), 1 ether);
            lendtroller.listToken(address(cPendlePT));
            // add MToken support on price router
            priceRouter.addMTokenSupport(address(cPendlePT));
            // set collateral token configuration
            lendtroller.updateCollateralToken(
                IMToken(address(cPendlePT)),
                7000,
                4000, // liquidate at 71%
                3000,
                200, // 2% liq incentive
                400,
                0,
                200
            );

            address[] memory mTokens = new address[](1);
            mTokens[0] = address(cPendlePT);
            uint256[] memory caps = new uint256[](1);
            caps[0] = 100 ether;
            lendtroller.setCTokenCollateralCaps(mTokens, caps);

            // address[] memory markets = new address[](1);
            // markets[0] = address(cPendlePT);
            // vm.prank(user1);
            // lendtroller.enterMarkets(markets);
            // vm.prank(user2);
            // lendtroller.enterMarkets(markets);
        }

        // provide enough liquidity
        provideEnoughLiquidityForLeverage();
    }

    function _preparePT(address user, uint256 amount) internal {
        deal(_PT_STETH, user, amount);
    }

    function provideEnoughLiquidityForLeverage() internal {
        address liquidityProvider = address(new User());
        _prepareUSDC(liquidityProvider, 200000e6);
        _preparePT(liquidityProvider, 10 ether);
        // mint dUSDC
        vm.startPrank(liquidityProvider);
        usdc.approve(address(dUSDC), 200000e6);
        dUSDC.mint(200000e6);
        // mint cBALETH
        pendlePT.approve(address(cPendlePT), 10 ether);
        cPendlePT.mint(10 ether, liquidityProvider);
        vm.stopPrank();
    }

    function testInitialize() public {
        assertEq(cPendlePT.isCToken(), true);
        assertEq(dUSDC.isCToken(), false);
    }

    function testCTokenMintRedeem() public {
        _preparePT(user1, 2 ether);

        // try mint()
        vm.startPrank(user1);
        pendlePT.approve(address(cPendlePT), 1 ether);
        cPendlePT.mint(1 ether, user1);
        vm.stopPrank();
        assertEq(cPendlePT.balanceOf(user1), 1 ether);

        // try mint()
        vm.startPrank(user1);
        pendlePT.approve(address(cPendlePT), 1 ether);
        cPendlePT.mint(1 ether, user2);
        vm.stopPrank();
        assertEq(cPendlePT.balanceOf(user1), 1 ether);
        assertEq(cPendlePT.balanceOf(user2), 1 ether);

        // try redeem()
        vm.startPrank(user1);
        cPendlePT.redeem(1 ether, user1, user1);
        vm.stopPrank();
        assertEq(cPendlePT.balanceOf(user1), 0);
    }

    function testDTokenMintRedeem() public {
        _prepareUSDC(user1, 2e6);

        // try mint()
        vm.startPrank(user1);
        usdc.approve(address(dUSDC), 1e6);
        dUSDC.mint(1e6);
        vm.stopPrank();
        assertEq(dUSDC.balanceOf(user1), 1e6);

        // try mintFor()
        vm.startPrank(user1);
        usdc.approve(address(dUSDC), 1e6);
        dUSDC.mintFor(1e6, user2);
        vm.stopPrank();
        assertEq(dUSDC.balanceOf(user1), 1e6);
        assertEq(dUSDC.balanceOf(user2), 1e6);

        // try redeem()
        vm.startPrank(user1);
        dUSDC.redeem(1e6);
        vm.stopPrank();
        assertEq(dUSDC.balanceOf(user1), 0);
    }

    function testDTokenBorrowRepay() public {
        _preparePT(user1, 1 ether);

        // try mint()
        vm.startPrank(user1);
        pendlePT.approve(address(cPendlePT), 1 ether);
        cPendlePT.mint(1 ether, user1);
        vm.stopPrank();
        AccountSnapshot memory snapshot = cPendlePT.getSnapshotPacked(user1);
        assertEq(cPendlePT.balanceOf(user1), 1 ether);
        assertEq(snapshot.debtBalance, 0);
        assertEq(snapshot.exchangeRate, 1 ether);

        vm.startPrank(user1);
        lendtroller.postCollateral(user1, address(cPendlePT), 1 ether);
        vm.stopPrank();

        // try borrow()
        vm.startPrank(user1);
        dUSDC.borrow(500e6);
        vm.stopPrank();
        assertEq(dUSDC.balanceOf(user1), 0);
        assertEq(dUSDC.debtBalanceCached(user1), 500e6);
        assertEq(dUSDC.exchangeRateCached(), 1 ether);

        // try borrow()
        skip(1200);
        vm.startPrank(user1);
        dUSDC.borrow(100e6);
        vm.stopPrank();
        assertEq(dUSDC.balanceOf(user1), 0);
        assertGt(dUSDC.debtBalanceCached(user1), 600e6);
        assertGt(dUSDC.exchangeRateCached(), 1 ether);

        // skip min hold period
        skip(20 minutes);

        // try partial repay
        (, uint256 borrowBalanceBefore, uint256 exchangeRateBefore) = dUSDC
            .getSnapshot(user1);
        _prepareUSDC(user1, 200e6);
        vm.startPrank(user1);
        usdc.approve(address(dUSDC), 200e6);
        dUSDC.repay(200e6);
        vm.stopPrank();
        assertEq(dUSDC.balanceOf(user1), 0);
        assertGt(dUSDC.debtBalanceCached(user1), borrowBalanceBefore - 200e6);
        assertGt(dUSDC.exchangeRateCached(), exchangeRateBefore);

        // skip some period
        skip(1200);

        // try repay full
        (, borrowBalanceBefore, exchangeRateBefore) = dUSDC.getSnapshot(user1);
        _prepareUSDC(user1, borrowBalanceBefore);
        vm.startPrank(user1);
        usdc.approve(address(dUSDC), borrowBalanceBefore);
        dUSDC.repay(borrowBalanceBefore);
        vm.stopPrank();
        assertEq(dUSDC.balanceOf(user1), 0);
        assertGt(dUSDC.debtBalanceCached(user1), 0);
        assertGt(dUSDC.exchangeRateCached(), exchangeRateBefore);
    }

    function testCTokenRedeemOnBorrow() public {
        _preparePT(user1, 1 ether);

        // try mint()
        vm.startPrank(user1);
        pendlePT.approve(address(cPendlePT), 1 ether);
        cPendlePT.mint(1 ether, user1);
        vm.stopPrank();

        vm.startPrank(user1);
        lendtroller.postCollateral(user1, address(cPendlePT), 1 ether);
        vm.stopPrank();

        // try borrow()
        vm.startPrank(user1);
        dUSDC.borrow(500e6);
        vm.stopPrank();

        // skip min hold period
        skip(20 minutes);

        // can't redeem full
        vm.startPrank(user1);
        vm.expectRevert(
            bytes4(keccak256("Lendtroller__InsufficientCollateral()"))
        );
        cPendlePT.redeem(1 ether, user1, user1);
        vm.stopPrank();

        // can redeem partially
        vm.startPrank(user1);
        cPendlePT.redeem(0.2 ether, user1, user1);
        vm.stopPrank();
        assertEq(cPendlePT.balanceOf(user1), 0.8 ether);
        assertEq(cPendlePT.exchangeRateCached(), 1 ether);
    }

    function testDTokenRedeemOnBorrow() public {
        // try mint()
        _preparePT(user1, 1 ether);
        vm.startPrank(user1);
        pendlePT.approve(address(cPendlePT), 1 ether);
        cPendlePT.mint(1 ether, user1);
        vm.stopPrank();

        vm.startPrank(user1);
        lendtroller.postCollateral(user1, address(cPendlePT), 1 ether);
        vm.stopPrank();

        // try mint()
        _prepareUSDC(user1, 1000e6);
        vm.startPrank(user1);
        usdc.approve(address(dUSDC), 1000e6);
        dUSDC.mint(1000e6);
        vm.stopPrank();

        // try borrow()
        vm.startPrank(user1);
        dUSDC.borrow(500e6);
        vm.stopPrank();

        // skip min hold period
        skip(20 minutes);

        // can redeem fully
        vm.startPrank(user1);
        dUSDC.redeem(1000e6);
        vm.stopPrank();

        assertEq(cPendlePT.balanceOf(user1), 1 ether);
        assertEq(cPendlePT.exchangeRateCached(), 1 ether);

        assertEq(dUSDC.balanceOf(user1), 0);
        assertGt(dUSDC.debtBalanceCached(user1), 500e6);
        assertGt(dUSDC.exchangeRateCached(), 1 ether);
    }

    function testCTokenTransferOnBorrow() public {
        _preparePT(user1, 1 ether);

        // try mint()
        vm.startPrank(user1);
        pendlePT.approve(address(cPendlePT), 1 ether);
        cPendlePT.mint(1 ether, user1);
        vm.stopPrank();

        vm.startPrank(user1);
        lendtroller.postCollateral(user1, address(cPendlePT), 1 ether);
        vm.stopPrank();

        // try borrow()
        vm.startPrank(user1);
        dUSDC.borrow(500e6);
        vm.stopPrank();

        // skip min hold period
        skip(20 minutes);

        // can't transfer full
        vm.startPrank(user1);
        vm.expectRevert(
            bytes4(keccak256("Lendtroller__InsufficientCollateral()"))
        );
        cPendlePT.transfer(user2, 1 ether);
        vm.stopPrank();

        // can redeem partially
        vm.startPrank(user1);
        cPendlePT.transfer(user2, 0.2 ether);
        vm.stopPrank();

        assertEq(cPendlePT.balanceOf(user1), 0.8 ether);
        assertEq(cPendlePT.balanceOf(user2), 0.2 ether);
        assertEq(cPendlePT.exchangeRateCached(), 1 ether);
    }

    function testDTokenTransferOnBorrow() public {
        // try mint()
        _preparePT(user1, 1 ether);
        vm.startPrank(user1);
        pendlePT.approve(address(cPendlePT), 1 ether);
        cPendlePT.mint(1 ether, user1);
        vm.stopPrank();

        vm.startPrank(user1);
        lendtroller.postCollateral(user1, address(cPendlePT), 1 ether);
        vm.stopPrank();

        // try mint()
        _prepareUSDC(user1, 1000e6);
        vm.startPrank(user1);
        usdc.approve(address(dUSDC), 1000e6);
        dUSDC.mint(1000e6);
        vm.stopPrank();

        // try borrow()
        vm.startPrank(user1);
        dUSDC.borrow(500e6);
        vm.stopPrank();

        // skip min hold period
        skip(20 minutes);

        // try full transfer
        vm.startPrank(user1);
        dUSDC.transfer(user2, 1000e6);
        vm.stopPrank();

        assertEq(cPendlePT.balanceOf(user1), 1 ether);
        assertEq(cPendlePT.exchangeRateCached(), 1 ether);

        assertEq(dUSDC.balanceOf(user1), 0);
        assertEq(dUSDC.debtBalanceCached(user1), 500e6);

        assertEq(dUSDC.balanceOf(user2), 1000e6);
        assertEq(dUSDC.debtBalanceCached(user2), 0);
        assertEq(dUSDC.exchangeRateCached(), 1 ether);
    }

    function testLiquidationExact() public {
        _preparePT(user1, 1 ether);

        // try mint()
        vm.startPrank(user1);
        pendlePT.approve(address(cPendlePT), 1 ether);
        cPendlePT.mint(1 ether, user1);
        vm.stopPrank();

        vm.startPrank(user1);
        lendtroller.postCollateral(user1, address(cPendlePT), 1 ether);
        vm.stopPrank();

        // try borrow()
        vm.startPrank(user1);
        dUSDC.borrow(1000e6);
        vm.stopPrank();

        // skip min hold period
        skip(20 minutes);

        (uint256 pendlePTPrice, ) = priceRouter.getPrice(
            address(pendlePT),
            true,
            true
        );

        mockUsdcFeed.setMockAnswer(120000000);

        // try liquidate half
        _prepareUSDC(user2, 250e6);
        vm.startPrank(user2);
        usdc.approve(address(dUSDC), 250e6);
        dUSDC.liquidateExact(user1, 250e6, IMToken(address(cPendlePT)));
        vm.stopPrank();

        uint256 liquidatedAmount = 250e6;
        assertApproxEqRel(
            cPendlePT.balanceOf(user1),
            1 ether - (liquidatedAmount * 12e11 * 1 ether) / pendlePTPrice,
            0.03e18
        );
        assertEq(cPendlePT.exchangeRateCached(), 1 ether);

        assertEq(dUSDC.balanceOf(user1), 0);
        assertApproxEqRel(dUSDC.debtBalanceCached(user1), 750e6, 0.01e18);
        assertApproxEqRel(dUSDC.exchangeRateCached(), 1 ether, 0.01e18);
    }

    function testLiquidationFull() public {
        _preparePT(user1, 1 ether);

        // try mint()
        vm.startPrank(user1);
        pendlePT.approve(address(cPendlePT), 1 ether);
        cPendlePT.mint(1 ether, user1);
        vm.stopPrank();

        vm.startPrank(user1);
        lendtroller.postCollateral(user1, address(cPendlePT), 1 ether);
        vm.stopPrank();

        // try borrow()
        vm.startPrank(user1);
        dUSDC.borrow(1000e6);
        vm.stopPrank();

        // skip min hold period
        skip(20 minutes);

        (uint256 pendlePTPrice, ) = priceRouter.getPrice(
            address(pendlePT),
            true,
            true
        );

        mockUsdcFeed.setMockAnswer(120000000);

        // try liquidate
        _prepareUSDC(user2, 1000e6);
        vm.startPrank(user2);
        usdc.approve(address(dUSDC), 1000e6);
        dUSDC.liquidate(user1, IMToken(address(cPendlePT)));
        vm.stopPrank();

        uint256 liquidatedAmount = 550e6;

        AccountSnapshot memory snapshot = cPendlePT.getSnapshotPacked(user1);
        assertApproxEqRel(
            cPendlePT.balanceOf(user1),
            1 ether - (liquidatedAmount * 12e11 * 1 ether) / pendlePTPrice,
            0.03e18
        );
        assertEq(snapshot.debtBalance, 0);
        assertEq(snapshot.exchangeRate, 1 ether);

        assertEq(dUSDC.balanceOf(user1), 0);
        assertApproxEqRel(
            dUSDC.debtBalanceCached(user1),
            1000e6 - liquidatedAmount,
            0.01e18
        );
        assertApproxEqRel(dUSDC.exchangeRateCached(), 1 ether, 0.01e18);
    }
}
