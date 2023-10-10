// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { IMToken, AccountSnapshot } from "contracts/interfaces/market/IMToken.sol";
import { IUniswapV2Router } from "contracts/interfaces/external/uniswap/IUniswapV2Router.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { MockDataFeed } from "contracts/mocks/MockDataFeed.sol";

import "tests/market/TestBaseMarket.sol";

contract User {}

contract TestTokensWithDifferentDecimals is TestBaseMarket {
    address internal constant _UNISWAP_V2_ROUTER =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    address public owner;

    receive() external payable {}

    fallback() external payable {}

    MockDataFeed public mockUsdcFeed;

    function setUp() public override {
        super.setUp();

        owner = address(this);

        // start epoch
        gaugePool.start(address(lendtroller));

        // deploy dUSDC
        {
            _deployDUSDC();
            // support market
            _prepareUSDC(owner, 200000e6);
            usdc.approve(address(dUSDC), 200000e6);
            lendtroller.listMarketToken(address(dUSDC));
            // add MToken support on price router
            priceRouter.addMTokenSupport(address(dUSDC));
            address[] memory markets = new address[](1);
            markets[0] = address(dUSDC);
            vm.prank(user1);
            lendtroller.enterMarkets(markets);
            vm.prank(user2);
            lendtroller.enterMarkets(markets);
        }

        // deploy CBALRETH
        {
            // deploy aura position vault
            _deployCBALRETH();

            // support market
            _prepareBALRETH(owner, 1 ether);
            balRETH.approve(address(cBALRETH), 1 ether);
            lendtroller.listMarketToken(address(cBALRETH));
            // add MToken support on price router
            priceRouter.addMTokenSupport(address(cBALRETH));
            // set collateral token configuration
            lendtroller.updateCollateralToken(
                IMToken(address(cBALRETH)),
                200, // 2% liq incentive
                0,
                4000, // liquidate at 71%
                3000,
                7000
            );
            address[] memory markets = new address[](1);
            markets[0] = address(cBALRETH);
            vm.prank(user1);
            lendtroller.enterMarkets(markets);
            vm.prank(user2);
            lendtroller.enterMarkets(markets);
        }

        // provide enough liquidity
        provideEnoughLiquidityForLeverage();

        centralRegistry.addSwapper(_UNISWAP_V2_ROUTER);

        // use mock pricing for testing
        mockUsdcFeed = new MockDataFeed(_CHAINLINK_USDC_USD);
        chainlinkAdaptor.addAsset(_USDC_ADDRESS, address(mockUsdcFeed), true);
        dualChainlinkAdaptor.addAsset(
            _USDC_ADDRESS,
            address(mockUsdcFeed),
            true
        );
    }

    function provideEnoughLiquidityForLeverage() internal {
        address liquidityProvider = address(new User());
        _prepareUSDC(liquidityProvider, 200000e6);
        _prepareBALRETH(liquidityProvider, 10 ether);
        // mint dUSDC
        vm.startPrank(liquidityProvider);
        usdc.approve(address(dUSDC), 200000e6);
        dUSDC.mint(200000e6);
        // mint cBALETH
        balRETH.approve(address(cBALRETH), 10 ether);
        cBALRETH.mint(10 ether);
        vm.stopPrank();
    }

    function testInitialize() public {
        assertEq(cBALRETH.isCToken(), true);
        assertEq(dUSDC.isCToken(), false);
    }

    function testCTokenMintRedeem() public {
        _prepareBALRETH(user1, 2 ether);

        // try mint()
        vm.startPrank(user1);
        balRETH.approve(address(cBALRETH), 1 ether);
        cBALRETH.mint(1 ether);
        vm.stopPrank();
        assertEq(cBALRETH.balanceOf(user1), 1 ether);

        // try mintFor()
        vm.startPrank(user1);
        balRETH.approve(address(cBALRETH), 1 ether);
        cBALRETH.mintFor(1 ether, user2);
        vm.stopPrank();
        assertEq(cBALRETH.balanceOf(user1), 1 ether);
        assertEq(cBALRETH.balanceOf(user2), 1 ether);

        // try redeem()
        vm.startPrank(user1);
        cBALRETH.redeem(1 ether);
        vm.stopPrank();
        assertEq(cBALRETH.balanceOf(user1), 0);
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
        _prepareBALRETH(user1, 1 ether);

        // try mint()
        vm.startPrank(user1);
        balRETH.approve(address(cBALRETH), 1 ether);
        cBALRETH.mint(1 ether);
        vm.stopPrank();
        AccountSnapshot memory snapshot = cBALRETH.getSnapshotPacked(user1);
        assertEq(snapshot.balance, 1 ether);
        assertEq(snapshot.debtBalance, 0);
        assertEq(snapshot.exchangeRate, 1 ether);

        // try borrow()
        vm.startPrank(user1);
        dUSDC.borrow(500e6);
        vm.stopPrank();
        snapshot = dUSDC.getSnapshotPacked(user1);
        assertEq(snapshot.balance, 0);
        assertEq(snapshot.debtBalance, 500e6);
        assertEq(snapshot.exchangeRate, 1 ether);

        // try borrow()
        skip(1200);
        vm.startPrank(user1);
        dUSDC.borrow(100e6);
        vm.stopPrank();
        snapshot = dUSDC.getSnapshotPacked(user1);
        assertEq(snapshot.balance, 0);
        assertGt(snapshot.debtBalance, 600e6);
        assertGt(snapshot.exchangeRate, 1 ether);

        // skip min hold period
        skip(900);

        // try partial repay
        (, uint256 borrowBalanceBefore, uint256 exchangeRateBefore) = dUSDC
            .getSnapshot(user1);
        _prepareUSDC(user1, 200e6);
        vm.startPrank(user1);
        usdc.approve(address(dUSDC), 200e6);
        dUSDC.repay(200e6);
        vm.stopPrank();
        snapshot = dUSDC.getSnapshotPacked(user1);
        assertEq(snapshot.balance, 0);
        assertGt(snapshot.debtBalance, borrowBalanceBefore - 200e6);
        assertGt(snapshot.exchangeRate, exchangeRateBefore);

        // skip some period
        skip(1200);

        // try repay full
        (, borrowBalanceBefore, exchangeRateBefore) = dUSDC.getSnapshot(user1);
        _prepareUSDC(user1, borrowBalanceBefore);
        vm.startPrank(user1);
        usdc.approve(address(dUSDC), borrowBalanceBefore);
        dUSDC.repay(borrowBalanceBefore);
        vm.stopPrank();
        snapshot = dUSDC.getSnapshotPacked(user1);
        assertEq(snapshot.balance, 0);
        assertGt(snapshot.debtBalance, 0);
        assertGt(snapshot.exchangeRate, exchangeRateBefore);
    }

    function testCTokenRedeemOnBorrow() public {
        _prepareBALRETH(user1, 1 ether);

        // try mint()
        vm.startPrank(user1);
        balRETH.approve(address(cBALRETH), 1 ether);
        cBALRETH.mint(1 ether);
        vm.stopPrank();

        // try borrow()
        vm.startPrank(user1);
        dUSDC.borrow(500e6);
        vm.stopPrank();

        // skip min hold period
        skip(900);

        // can't redeem full
        vm.startPrank(user1);
        vm.expectRevert(
            bytes4(keccak256("Lendtroller__InsufficientLiquidity()"))
        );
        cBALRETH.redeem(1 ether);
        vm.stopPrank();

        // can redeem partially
        vm.startPrank(user1);
        cBALRETH.redeem(0.2 ether);
        vm.stopPrank();
        AccountSnapshot memory snapshot = cBALRETH.getSnapshotPacked(user1);
        assertEq(snapshot.balance, 0.8 ether);
        assertEq(snapshot.debtBalance, 0 ether);
        assertEq(snapshot.exchangeRate, 1 ether);
    }

    function testDTokenRedeemOnBorrow() public {
        // try mint()
        _prepareBALRETH(user1, 1 ether);
        vm.startPrank(user1);
        balRETH.approve(address(cBALRETH), 1 ether);
        cBALRETH.mint(1 ether);
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
        skip(900);

        // can redeem fully
        vm.startPrank(user1);
        dUSDC.redeem(1000e6);
        vm.stopPrank();

        AccountSnapshot memory snapshot = cBALRETH.getSnapshotPacked(user1);
        assertEq(snapshot.balance, 1 ether);
        assertEq(snapshot.debtBalance, 0);
        assertEq(snapshot.exchangeRate, 1 ether);

        snapshot = dUSDC.getSnapshotPacked(user1);
        assertEq(snapshot.balance, 0);
        assertGt(snapshot.debtBalance, 500e6);
        assertGt(snapshot.exchangeRate, 1 ether);
    }

    function testCTokenTransferOnBorrow() public {
        _prepareBALRETH(user1, 1 ether);

        // try mint()
        vm.startPrank(user1);
        balRETH.approve(address(cBALRETH), 1 ether);
        cBALRETH.mint(1 ether);
        vm.stopPrank();

        // try borrow()
        vm.startPrank(user1);
        dUSDC.borrow(500e6);
        vm.stopPrank();

        // skip min hold period
        skip(900);

        // can't transfer full
        vm.startPrank(user1);
        vm.expectRevert(
            bytes4(keccak256("Lendtroller__InsufficientLiquidity()"))
        );
        cBALRETH.transfer(user2, 1 ether);
        vm.stopPrank();

        // can redeem partially
        vm.startPrank(user1);
        cBALRETH.transfer(user2, 0.2 ether);
        vm.stopPrank();
        AccountSnapshot memory snapshot = cBALRETH.getSnapshotPacked(user1);
        assertEq(snapshot.balance, 0.8 ether);
        assertEq(snapshot.debtBalance, 0 ether);
        assertEq(snapshot.exchangeRate, 1 ether);
        snapshot = cBALRETH.getSnapshotPacked(user2);
        assertEq(snapshot.balance, 0.2 ether);
        assertEq(snapshot.debtBalance, 0 ether);
        assertEq(snapshot.exchangeRate, 1 ether);
    }

    function testDTokenTransferOnBorrow() public {
        // try mint()
        _prepareBALRETH(user1, 1 ether);
        vm.startPrank(user1);
        balRETH.approve(address(cBALRETH), 1 ether);
        cBALRETH.mint(1 ether);
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
        skip(900);

        // try full transfer
        vm.startPrank(user1);
        dUSDC.transfer(user2, 1000e6);
        vm.stopPrank();

        AccountSnapshot memory snapshot = cBALRETH.getSnapshotPacked(user1);
        assertEq(snapshot.balance, 1 ether);
        assertEq(snapshot.debtBalance, 0);
        assertEq(snapshot.exchangeRate, 1 ether);

        snapshot = dUSDC.getSnapshotPacked(user1);
        assertEq(snapshot.balance, 0);
        assertEq(snapshot.debtBalance, 500e6);
        assertEq(snapshot.exchangeRate, 1 ether);

        snapshot = dUSDC.getSnapshotPacked(user2);
        assertEq(snapshot.balance, 1000e6);
        assertEq(snapshot.debtBalance, 0);
        assertEq(snapshot.exchangeRate, 1 ether);
    }

    function testLiquidationExact() public {
        _prepareBALRETH(user1, 1 ether);

        // try mint()
        vm.startPrank(user1);
        balRETH.approve(address(cBALRETH), 1 ether);
        cBALRETH.mint(1 ether);
        vm.stopPrank();

        // try borrow()
        vm.startPrank(user1);
        dUSDC.borrow(1000e6);
        vm.stopPrank();

        // skip min hold period
        skip(900);

        (uint256 balRETHPrice, ) = priceRouter.getPrice(
            address(balRETH),
            true,
            true
        );

        mockUsdcFeed.setMockAnswer(200000000);

        // try liquidate half
        _prepareUSDC(user2, 250e6);
        vm.startPrank(user2);
        usdc.approve(address(dUSDC), 250e6);
        dUSDC.liquidateExact(user1, 250e6, IMToken(address(cBALRETH)));
        vm.stopPrank();

        AccountSnapshot memory snapshot = cBALRETH.getSnapshotPacked(user1);
        assertApproxEqRel(
            snapshot.balance,
            1 ether - (500 ether * 1 ether) / balRETHPrice,
            0.01e18
        );
        assertEq(snapshot.debtBalance, 0);
        assertEq(snapshot.exchangeRate, 1 ether);

        snapshot = dUSDC.getSnapshotPacked(user1);
        assertEq(snapshot.balance, 0);
        assertApproxEqRel(snapshot.debtBalance, 750e6, 0.01e18);
        assertApproxEqRel(snapshot.exchangeRate, 1 ether, 0.01e18);
    }

    function testLiquidation() public {
        _prepareBALRETH(user1, 1 ether);

        // try mint()
        vm.startPrank(user1);
        balRETH.approve(address(cBALRETH), 1 ether);
        cBALRETH.mint(1 ether);
        vm.stopPrank();

        // try borrow()
        vm.startPrank(user1);
        dUSDC.borrow(1000e6);
        vm.stopPrank();

        // skip min hold period
        skip(900);

        (uint256 balRETHPrice, ) = priceRouter.getPrice(
            address(balRETH),
            true,
            true
        );

        mockUsdcFeed.setMockAnswer(200000000);

        // try liquidate
        _prepareUSDC(user2, 600e6);
        vm.startPrank(user2);
        usdc.approve(address(dUSDC), 600e6);
        dUSDC.liquidate(user1, IMToken(address(cBALRETH)));
        vm.stopPrank();

        AccountSnapshot memory snapshot = cBALRETH.getSnapshotPacked(user1);
        assertApproxEqRel(
            snapshot.balance,
            1 ether - (1000 ether * 1 ether) / balRETHPrice,
            0.03e18
        );
        assertEq(snapshot.debtBalance, 0);
        assertEq(snapshot.exchangeRate, 1 ether);

        snapshot = dUSDC.getSnapshotPacked(user1);
        assertEq(snapshot.balance, 0);
        assertApproxEqRel(snapshot.debtBalance, 500e6, 0.01e18);
        assertApproxEqRel(snapshot.exchangeRate, 1 ether, 0.01e18);
    }
}
