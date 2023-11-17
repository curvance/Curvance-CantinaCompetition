// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { IMToken, AccountSnapshot } from "contracts/interfaces/market/IMToken.sol";
import { MockDataFeed } from "contracts/mocks/MockDataFeed.sol";
import "tests/market/TestBaseMarket.sol";

contract TestTokensWithDifferentDecimals is TestBaseMarket {
    address public owner;

    receive() external payable {}

    fallback() external payable {}

    MockDataFeed public mockUsdcFeed;
    MockDataFeed public mockWethFeed;
    MockDataFeed public mockRethFeed;

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
        mockRethFeed = new MockDataFeed(_CHAINLINK_RETH_ETH);
        chainlinkAdaptor.addAsset(_RETH_ADDRESS, address(mockRethFeed), false);
        dualChainlinkAdaptor.addAsset(
            _RETH_ADDRESS,
            address(mockRethFeed),
            true
        );

        // start epoch
        gaugePool.start(address(lendtroller));
        vm.warp(gaugePool.startTime());
        vm.roll(block.number + 1000);

        mockUsdcFeed.setMockUpdatedAt(block.timestamp);
        mockWethFeed.setMockUpdatedAt(block.timestamp);
        mockRethFeed.setMockUpdatedAt(block.timestamp);

        // setup dUSDC
        {
            // support market
            _prepareUSDC(owner, 200000e6);
            usdc.approve(address(dUSDC), 200000e6);
            lendtroller.listToken(address(dUSDC));
        }

        // setup CBALRETH
        {
            // support market
            _prepareBALRETH(owner, 1 ether);
            balRETH.approve(address(cBALRETH), 1 ether);
            lendtroller.listToken(address(cBALRETH));
            // set collateral factor
            lendtroller.updateCollateralToken(
                IMToken(address(cBALRETH)),
                7000,
                4000,
                3000,
                200,
                200,
                100,
                1000
            );
            address[] memory tokens = new address[](1);
            tokens[0] = address(cBALRETH);
            uint256[] memory caps = new uint256[](1);
            caps[0] = 100_000e18;
            lendtroller.setCTokenCollateralCaps(tokens, caps);
        }

        // provide enough liquidity
        provideEnoughLiquidityForLeverage();
    }

    function provideEnoughLiquidityForLeverage() internal {
        address liquidityProvider = makeAddr("liquidityProvider");
        _prepareUSDC(liquidityProvider, 200000e6);
        _prepareBALRETH(liquidityProvider, 10 ether);
        // mint dUSDC
        vm.startPrank(liquidityProvider);
        usdc.approve(address(dUSDC), 200000e6);
        dUSDC.mint(200000e6);
        // mint cBALETH
        balRETH.approve(address(cBALRETH), 10 ether);
        cBALRETH.deposit(10 ether, liquidityProvider);
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
        cBALRETH.deposit(1 ether, user1);
        lendtroller.postCollateral(user1, address(cBALRETH), 1 ether - 1);
        vm.stopPrank();
        assertEq(cBALRETH.balanceOf(user1), 1 ether);

        // try mintFor()
        vm.startPrank(user1);
        balRETH.approve(address(cBALRETH), 1 ether);
        cBALRETH.deposit(1 ether, user2);
        vm.stopPrank();
        assertEq(cBALRETH.balanceOf(user1), 1 ether);
        assertEq(cBALRETH.balanceOf(user2), 1 ether);

        // skip some period
        skip(20 minutes);

        // try redeem()
        vm.startPrank(user1);
        cBALRETH.redeem(1 ether, user1, user1);
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
        cBALRETH.deposit(1 ether, user1);
        lendtroller.postCollateral(user1, address(cBALRETH), 1 ether - 1);
        vm.stopPrank();
        AccountSnapshot memory snapshot = cBALRETH.getSnapshotPacked(user1);
        assertEq(cBALRETH.balanceOf(user1), 1 ether);
        assertEq(snapshot.debtBalance, 0);
        assertEq(snapshot.exchangeRate, 1 ether);

        // try borrow()
        vm.startPrank(user1);
        dUSDC.borrow(500e6);
        vm.stopPrank();
        snapshot = dUSDC.getSnapshotPacked(user1);
        assertEq(dUSDC.balanceOf(user1), 0);
        assertEq(snapshot.debtBalance, 500e6);
        assertEq(snapshot.exchangeRate, 1 ether);

        // try borrow()
        skip(1200);
        vm.startPrank(user1);
        dUSDC.borrow(100e6);
        vm.stopPrank();
        snapshot = dUSDC.getSnapshotPacked(user1);
        assertEq(dUSDC.balanceOf(user1), 0);
        assertGt(snapshot.debtBalance, 600e6);
        assertGt(snapshot.exchangeRate, 1 ether);

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
        snapshot = dUSDC.getSnapshotPacked(user1);
        assertEq(dUSDC.balanceOf(user1), 0);
        assertGt(snapshot.debtBalance, borrowBalanceBefore - 200e6);
        assertGt(snapshot.exchangeRate, exchangeRateBefore);

        // skip some period
        skip(20 minutes);

        // try repay full
        (, borrowBalanceBefore, exchangeRateBefore) = dUSDC.getSnapshot(user1);
        _prepareUSDC(user1, borrowBalanceBefore);
        vm.startPrank(user1);
        usdc.approve(address(dUSDC), borrowBalanceBefore);
        dUSDC.repay(borrowBalanceBefore);
        vm.stopPrank();
        snapshot = dUSDC.getSnapshotPacked(user1);
        assertEq(dUSDC.balanceOf(user1), 0);
        assertGt(snapshot.debtBalance, 0);
        assertGt(snapshot.exchangeRate, exchangeRateBefore);
    }

    function testCTokenRedeemOnBorrow() public {
        _prepareBALRETH(user1, 1 ether);

        // try mint()
        vm.startPrank(user1);
        balRETH.approve(address(cBALRETH), 1 ether);
        cBALRETH.deposit(1 ether, user1);
        lendtroller.postCollateral(user1, address(cBALRETH), 1 ether - 1);
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
            bytes4(keccak256("Lendtroller__InsufficientLiquidity()"))
        );
        cBALRETH.redeem(1 ether, user1, user1);
        vm.stopPrank();

        // can redeem partially
        vm.startPrank(user1);
        cBALRETH.redeem(0.2 ether, user1, user1);
        vm.stopPrank();
        AccountSnapshot memory snapshot = cBALRETH.getSnapshotPacked(user1);
        assertEq(cBALRETH.balanceOf(user1), 0.8 ether);
        assertEq(snapshot.debtBalance, 0 ether);
        assertEq(snapshot.exchangeRate, 1 ether);
    }

    function testDTokenRedeemOnBorrow() public {
        // try mint()
        _prepareBALRETH(user1, 1 ether);
        vm.startPrank(user1);
        balRETH.approve(address(cBALRETH), 1 ether);
        cBALRETH.deposit(1 ether, user1);
        lendtroller.postCollateral(user1, address(cBALRETH), 1 ether - 1);
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

        AccountSnapshot memory snapshot = cBALRETH.getSnapshotPacked(user1);
        assertEq(cBALRETH.balanceOf(user1), 1 ether);
        assertEq(snapshot.debtBalance, 0);
        assertEq(snapshot.exchangeRate, 1 ether);

        snapshot = dUSDC.getSnapshotPacked(user1);
        assertEq(dUSDC.balanceOf(user1), 0);
        assertGt(snapshot.debtBalance, 500e6);
        assertGt(snapshot.exchangeRate, 1 ether);
    }

    function testCTokenTransferOnBorrow() public {
        _prepareBALRETH(user1, 1 ether);

        // try mint()
        vm.startPrank(user1);
        balRETH.approve(address(cBALRETH), 1 ether);
        cBALRETH.deposit(1 ether, user1);
        lendtroller.postCollateral(user1, address(cBALRETH), 1 ether - 1);
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
            bytes4(keccak256("Lendtroller__InsufficientLiquidity()"))
        );
        cBALRETH.transfer(user2, 1 ether);
        vm.stopPrank();

        // can redeem partially
        vm.startPrank(user1);
        cBALRETH.transfer(user2, 0.2 ether);
        vm.stopPrank();
        AccountSnapshot memory snapshot = cBALRETH.getSnapshotPacked(user1);
        assertEq(cBALRETH.balanceOf(user1), 0.8 ether);
        assertEq(snapshot.debtBalance, 0 ether);
        assertEq(snapshot.exchangeRate, 1 ether);
        snapshot = cBALRETH.getSnapshotPacked(user2);
        assertEq(cBALRETH.balanceOf(user2), 0.2 ether);
        assertEq(snapshot.debtBalance, 0 ether);
        assertEq(snapshot.exchangeRate, 1 ether);
    }

    function testDTokenTransferOnBorrow() public {
        // try mint()
        _prepareBALRETH(user1, 1 ether);
        vm.startPrank(user1);
        balRETH.approve(address(cBALRETH), 1 ether);
        cBALRETH.deposit(1 ether, user1);
        lendtroller.postCollateral(user1, address(cBALRETH), 1 ether - 1);
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

        AccountSnapshot memory snapshot = cBALRETH.getSnapshotPacked(user1);
        assertEq(cBALRETH.balanceOf(user1), 1 ether);
        assertEq(snapshot.debtBalance, 0);
        assertEq(snapshot.exchangeRate, 1 ether);

        snapshot = dUSDC.getSnapshotPacked(user1);
        assertEq(dUSDC.balanceOf(user1), 0);
        assertEq(snapshot.debtBalance, 500e6);
        assertEq(snapshot.exchangeRate, 1 ether);

        snapshot = dUSDC.getSnapshotPacked(user2);
        assertEq(dUSDC.balanceOf(user2), 1000e6);
        assertEq(snapshot.debtBalance, 0);
        assertEq(snapshot.exchangeRate, 1 ether);
    }

    function testLiquidationExact() public {
        _prepareBALRETH(user1, 1 ether);

        // try mint()
        vm.startPrank(user1);
        balRETH.approve(address(cBALRETH), 1 ether);
        cBALRETH.deposit(1 ether, user1);
        lendtroller.postCollateral(user1, address(cBALRETH), 1 ether - 1);
        vm.stopPrank();

        // try borrow()
        vm.startPrank(user1);
        dUSDC.borrow(1000e6);
        vm.stopPrank();

        // skip min hold period
        skip(20 minutes);

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
            cBALRETH.balanceOf(user1),
            1 ether - (500 ether * 1 ether) / balRETHPrice,
            0.01e18
        );
        assertEq(snapshot.debtBalance, 0);
        assertEq(snapshot.exchangeRate, 1 ether);

        snapshot = dUSDC.getSnapshotPacked(user1);
        assertEq(dUSDC.balanceOf(user1), 0);
        assertApproxEqRel(snapshot.debtBalance, 750e6, 0.01e18);
        assertApproxEqRel(snapshot.exchangeRate, 1 ether, 0.01e18);
    }

    function testLiquidation() public {
        _prepareBALRETH(user1, 1 ether);

        // try mint()
        vm.startPrank(user1);
        balRETH.approve(address(cBALRETH), 1 ether);
        cBALRETH.deposit(1 ether, user1);
        lendtroller.postCollateral(user1, address(cBALRETH), 1 ether - 1);
        vm.stopPrank();

        // try borrow()
        vm.startPrank(user1);
        dUSDC.borrow(1000e6);
        vm.stopPrank();

        // skip min hold period
        skip(20 minutes);

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
            cBALRETH.balanceOf(user1),
            1 ether - (1000 ether * 1 ether) / balRETHPrice,
            0.03e18
        );
        assertEq(snapshot.debtBalance, 0);
        assertEq(snapshot.exchangeRate, 1 ether);

        snapshot = dUSDC.getSnapshotPacked(user1);
        assertEq(dUSDC.balanceOf(user1), 0);
        assertApproxEqRel(snapshot.debtBalance, 500e6, 0.01e18);
        assertApproxEqRel(snapshot.exchangeRate, 1 ether, 0.01e18);
    }
}
