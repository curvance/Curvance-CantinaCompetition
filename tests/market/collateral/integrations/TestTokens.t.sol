// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { IMToken, AccountSnapshot } from "contracts/interfaces/market/IMToken.sol";
import { MockDataFeed } from "contracts/mocks/MockDataFeed.sol";

import "tests/market/TestBaseMarket.sol";

contract TestTokens is TestBaseMarket {
    address public owner;

    receive() external payable {}

    fallback() external payable {}

    MockDataFeed public mockDaiFeed;
    MockDataFeed public mockWethFeed;
    MockDataFeed public mockRethFeed;

    function setUp() public override {
        super.setUp();

        owner = address(this);

        // use mock pricing for testing
        mockDaiFeed = new MockDataFeed(_CHAINLINK_DAI_USD);
        chainlinkAdaptor.addAsset(_DAI_ADDRESS, address(mockDaiFeed), true);
        dualChainlinkAdaptor.addAsset(
            _DAI_ADDRESS,
            address(mockDaiFeed),
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

        mockDaiFeed.setMockUpdatedAt(block.timestamp);
        mockWethFeed.setMockUpdatedAt(block.timestamp);
        mockRethFeed.setMockUpdatedAt(block.timestamp);

        // setup dDAI
        {
            _prepareDAI(owner, 200000e18);
            dai.approve(address(dDAI), 200000e18);
            lendtroller.listToken(address(dDAI));
            // add MToken support on price router
            priceRouter.addMTokenSupport(address(dDAI));
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
        }

        // provide enough liquidity
        provideEnoughLiquidityForLeverage();
    }

    function provideEnoughLiquidityForLeverage() internal {
        address liquidityProvider = makeAddr("liquidityProvider");
        _prepareDAI(liquidityProvider, 200000e18);
        _prepareBALRETH(liquidityProvider, 10 ether);
        // mint dDAI
        vm.startPrank(liquidityProvider);
        dai.approve(address(dDAI), 200000 ether);
        dDAI.mint(200000 ether);
        // mint cBALETH
        balRETH.approve(address(cBALRETH), 10 ether);
        cBALRETH.mint(10 ether);
        vm.stopPrank();
    }

    function testInitialize() public {
        assertEq(cBALRETH.isCToken(), true);
        assertEq(dDAI.isCToken(), false);
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
        _prepareDAI(user1, 2 ether);

        // try mint()
        vm.startPrank(user1);
        dai.approve(address(dDAI), 1 ether);
        dDAI.mint(1 ether);
        vm.stopPrank();
        assertEq(dDAI.balanceOf(user1), 1 ether);

        // try mintFor()
        vm.startPrank(user1);
        dai.approve(address(dDAI), 1 ether);
        dDAI.mintFor(1 ether, user2);
        vm.stopPrank();
        assertEq(dDAI.balanceOf(user1), 1 ether);
        assertEq(dDAI.balanceOf(user2), 1 ether);

        // try redeem()
        vm.startPrank(user1);
        dDAI.redeem(1 ether);
        vm.stopPrank();
        assertEq(dDAI.balanceOf(user1), 0);
    }

    function testDTokenBorrowRepay() public {
        _prepareBALRETH(user1, 1 ether);

        // try mint()
        vm.startPrank(user1);
        balRETH.approve(address(cBALRETH), 1 ether);
        cBALRETH.mint(1 ether);
        lendtroller.postCollateral(user1, address(cBALRETH), 1 ether - 1);
        vm.stopPrank();
        AccountSnapshot memory snapshot = cBALRETH.getSnapshotPacked(user1);
        assertEq(cBALRETH.balanceOf(user1), 1 ether);
        assertEq(snapshot.debtBalance, 0);
        assertEq(snapshot.exchangeRate, 1 ether);

        // try borrow()
        vm.startPrank(user1);
        dDAI.borrow(500 ether);
        vm.stopPrank();
        snapshot = dDAI.getSnapshotPacked(user1);
        assertEq(dDAI.balanceOf(user1), 0);
        assertEq(snapshot.debtBalance, 500 ether);
        assertEq(snapshot.exchangeRate, 1 ether);

        // try borrow()
        skip(1200);
        vm.startPrank(user1);
        dDAI.borrow(100 ether);
        vm.stopPrank();
        snapshot = dDAI.getSnapshotPacked(user1);
        assertEq(dDAI.balanceOf(user1), 0);
        assertGt(snapshot.debtBalance, 600 ether);
        assertGt(snapshot.exchangeRate, 1 ether);

        // skip min hold period
        skip(20 minutes);

        // try partial repay
        (, uint256 borrowBalanceBefore, uint256 exchangeRateBefore) = dDAI
            .getSnapshot(user1);
        _prepareDAI(user1, 200 ether);
        vm.startPrank(user1);
        dai.approve(address(dDAI), 200 ether);
        dDAI.repay(200 ether);
        vm.stopPrank();
        snapshot = dDAI.getSnapshotPacked(user1);
        assertEq(dDAI.balanceOf(user1), 0);
        assertGt(snapshot.debtBalance, borrowBalanceBefore - 200 ether);
        assertGt(snapshot.exchangeRate, exchangeRateBefore);

        // skip some period
        skip(1200);

        // try repay full
        (, borrowBalanceBefore, exchangeRateBefore) = dDAI.getSnapshot(user1);
        _prepareDAI(user1, borrowBalanceBefore);
        vm.startPrank(user1);
        dai.approve(address(dDAI), borrowBalanceBefore);
        dDAI.repay(borrowBalanceBefore);
        vm.stopPrank();
        snapshot = dDAI.getSnapshotPacked(user1);
        assertEq(dDAI.balanceOf(user1), 0);
        assertGt(snapshot.debtBalance, 0);
        assertGt(snapshot.exchangeRate, exchangeRateBefore);
    }

    function testCTokenRedeemOnBorrow() public {
        _prepareBALRETH(user1, 1 ether);

        // try mint()
        vm.startPrank(user1);
        balRETH.approve(address(cBALRETH), 1 ether);
        cBALRETH.mint(1 ether);
        lendtroller.postCollateral(user1, address(cBALRETH), 1 ether - 1);
        vm.stopPrank();

        // try borrow()
        vm.startPrank(user1);
        dDAI.borrow(500 ether);
        vm.stopPrank();

        // skip min hold period
        skip(20 minutes);

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
        assertEq(cBALRETH.balanceOf(user1), 0.8 ether);
        assertEq(snapshot.debtBalance, 0 ether);
        assertEq(snapshot.exchangeRate, 1 ether);
    }

    function testDTokenRedeemOnBorrow() public {
        // try mint()
        _prepareBALRETH(user1, 1 ether);
        vm.startPrank(user1);
        balRETH.approve(address(cBALRETH), 1 ether);
        cBALRETH.mint(1 ether);
        lendtroller.postCollateral(user1, address(cBALRETH), 1 ether - 1);
        vm.stopPrank();

        // try mint()
        _prepareDAI(user1, 1000 ether);
        vm.startPrank(user1);
        dai.approve(address(dDAI), 1000 ether);
        dDAI.mint(1000 ether);
        vm.stopPrank();

        // try borrow()
        vm.startPrank(user1);
        dDAI.borrow(500 ether);
        vm.stopPrank();

        // skip min hold period
        skip(20 minutes);

        // can redeem fully
        vm.startPrank(user1);
        dDAI.redeem(1000 ether);
        vm.stopPrank();

        AccountSnapshot memory snapshot = cBALRETH.getSnapshotPacked(user1);
        assertEq(cBALRETH.balanceOf(user1), 1 ether);
        assertEq(snapshot.debtBalance, 0);
        assertEq(snapshot.exchangeRate, 1 ether);

        snapshot = dDAI.getSnapshotPacked(user1);
        assertEq(dDAI.balanceOf(user1), 0);
        assertGt(snapshot.debtBalance, 500 ether);
        assertGt(snapshot.exchangeRate, 1 ether);
    }

    function testCTokenTransferOnBorrow() public {
        _prepareBALRETH(user1, 1 ether);

        // try mint()
        vm.startPrank(user1);
        balRETH.approve(address(cBALRETH), 1 ether);
        cBALRETH.mint(1 ether);
        lendtroller.postCollateral(user1, address(cBALRETH), 1 ether - 1);
        vm.stopPrank();

        // try borrow()
        vm.startPrank(user1);
        dDAI.borrow(500 ether);
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
        cBALRETH.mint(1 ether);
        lendtroller.postCollateral(user1, address(cBALRETH), 1 ether - 1);
        vm.stopPrank();

        // try mint()
        _prepareDAI(user1, 1000 ether);
        vm.startPrank(user1);
        dai.approve(address(dDAI), 1000 ether);
        dDAI.mint(1000 ether);
        vm.stopPrank();

        // try borrow()
        vm.startPrank(user1);
        dDAI.borrow(500 ether);
        vm.stopPrank();

        // skip min hold period
        skip(20 minutes);

        // try full transfer
        vm.startPrank(user1);
        dDAI.transfer(user2, 1000 ether);
        vm.stopPrank();

        AccountSnapshot memory snapshot = cBALRETH.getSnapshotPacked(user1);
        assertEq(cBALRETH.balanceOf(user1), 1 ether);
        assertEq(snapshot.debtBalance, 0);
        assertEq(snapshot.exchangeRate, 1 ether);

        snapshot = dDAI.getSnapshotPacked(user1);
        assertEq(dDAI.balanceOf(user1), 0);
        assertEq(snapshot.debtBalance, 500 ether);
        assertEq(snapshot.exchangeRate, 1 ether);

        snapshot = dDAI.getSnapshotPacked(user2);
        assertEq(dDAI.balanceOf(user1), 1000 ether);
        assertEq(snapshot.debtBalance, 0 ether);
        assertEq(snapshot.exchangeRate, 1 ether);
    }

    function testLiquidationExact() public {
        _prepareBALRETH(user1, 1 ether);

        // try mint()
        vm.startPrank(user1);
        balRETH.approve(address(cBALRETH), 1 ether);
        cBALRETH.mint(1 ether);
        lendtroller.postCollateral(user1, address(cBALRETH), 1 ether - 1);
        vm.stopPrank();

        // try borrow()
        vm.startPrank(user1);
        dDAI.borrow(1000 ether);
        vm.stopPrank();

        // skip min hold period
        skip(20 minutes);

        (uint256 balRETHPrice, ) = priceRouter.getPrice(
            address(balRETH),
            true,
            true
        );

        mockDaiFeed.setMockAnswer(200000000);

        // try liquidate half
        _prepareDAI(user2, 250 ether);
        vm.startPrank(user2);
        dai.approve(address(dDAI), 250 ether);
        dDAI.liquidateExact(user1, 250 ether, IMToken(address(cBALRETH)));
        vm.stopPrank();

        AccountSnapshot memory snapshot = cBALRETH.getSnapshotPacked(user1);
        assertApproxEqRel(
            cBALRETH.balanceOf(user1),
            1 ether - (500 ether * 1 ether) / balRETHPrice,
            0.01e18
        );
        assertEq(snapshot.debtBalance, 0);
        assertEq(snapshot.exchangeRate, 1 ether);

        snapshot = dDAI.getSnapshotPacked(user1);
        assertEq(dDAI.balanceOf(user1), 0);
        assertApproxEqRel(snapshot.debtBalance, 750 ether, 0.01e18);
        assertApproxEqRel(snapshot.exchangeRate, 1 ether, 0.01e18);
    }

    function testLiquidation() public {
        _prepareBALRETH(user1, 1 ether);

        // try mint()
        vm.startPrank(user1);
        balRETH.approve(address(cBALRETH), 1 ether);
        cBALRETH.mint(1 ether);
        lendtroller.postCollateral(user1, address(cBALRETH), 1 ether - 1);
        vm.stopPrank();

        // try borrow()
        vm.startPrank(user1);
        dDAI.borrow(1000 ether);
        vm.stopPrank();

        // skip min hold period
        skip(20 minutes);

        (uint256 balRETHPrice, ) = priceRouter.getPrice(
            address(balRETH),
            true,
            true
        );

        mockDaiFeed.setMockAnswer(200000000);

        // try liquidate
        _prepareDAI(user2, 600 ether);
        vm.startPrank(user2);
        dai.approve(address(dDAI), 600 ether);
        dDAI.liquidate(user1, IMToken(address(cBALRETH)));
        vm.stopPrank();

        AccountSnapshot memory snapshot = cBALRETH.getSnapshotPacked(user1);
        assertApproxEqRel(
            cBALRETH.balanceOf(user1),
            1 ether - (1000 ether * 1 ether) / balRETHPrice,
            0.03e18
        );
        assertEq(snapshot.debtBalance, 0);
        assertEq(snapshot.exchangeRate, 1 ether);

        snapshot = dDAI.getSnapshotPacked(user1);
        assertEq(dDAI.balanceOf(user1), 0);
        assertApproxEqRel(snapshot.debtBalance, 500 ether, 0.01e18);
        assertApproxEqRel(snapshot.exchangeRate, 1 ether, 0.01e18);
    }
}
