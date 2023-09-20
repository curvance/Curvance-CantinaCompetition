// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { IMToken, AccountSnapshot } from "contracts/interfaces/market/IMToken.sol";
import { IUniswapV2Router } from "contracts/interfaces/external/uniswap/IUniswapV2Router.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { MockDataFeed } from "contracts/mocks/MockDataFeed.sol";

import "tests/market/TestBaseMarket.sol";

contract User {}

contract TestTokens is TestBaseMarket {
    address internal constant _UNISWAP_V2_ROUTER =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    address public owner;

    receive() external payable {}

    fallback() external payable {}

    MockDataFeed public mockDaiFeed;
    MockDataFeed public mockEthFeed;
    MockDataFeed public mockRethFeed;

    function setUp() public override {
        super.setUp();

        owner = address(this);

        // start epoch
        gaugePool.start(address(lendtroller));

        // deploy dDAI
        {
            _deployDDAI();
            // support market
            _prepareDAI(owner, 200000e18);
            dai.approve(address(dDAI), 200000e18);
            lendtroller.listMarketToken(address(dDAI));
            // add MToken support on price router
            priceRouter.addMTokenSupport(address(dDAI));
            address[] memory markets = new address[](1);
            markets[0] = address(dDAI);
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
            // set collateral factor
            lendtroller.updateCollateralToken(
                IMToken(address(cBALRETH)),
                200,
                0,
                5000
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
        // mockDaiFeed = new MockDataFeed(_CHAINLINK_DAI_USD);
        // mockEthFeed = new MockDataFeed(_CHAINLINK_ETH_USD);
        // mockRethFeed = new MockDataFeed(_CHAINLINK_RETH_ETH);
        // chainlinkAdaptor.addAsset(_DAI_ADDRESS, address(mockDaiFeed), true);
        // chainlinkAdaptor.addAsset(_WETH_ADDRESS, address(mockEthFeed), true);
        // chainlinkAdaptor.addAsset(_RETH_ADDRESS, address(mockRethFeed), true);
    }

    function provideEnoughLiquidityForLeverage() internal {
        address liquidityProvider = address(new User());
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
        assertEq(dDAI.isDToken(), true);
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

        // try redeemUnderlying()
        vm.startPrank(user2);
        cBALRETH.redeemUnderlying(1 ether);
        vm.stopPrank();
        assertEq(cBALRETH.balanceOf(user2), 0);
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

        // try redeemUnderlying()
        vm.startPrank(user2);
        dDAI.redeemUnderlying(1 ether);
        vm.stopPrank();
        assertEq(dDAI.balanceOf(user2), 0);
    }

    function testDTokenBorrowRepay() public {
        _prepareBALRETH(user1, 1 ether);

        // try mint()
        vm.startPrank(user1);
        balRETH.approve(address(cBALRETH), 1 ether);
        cBALRETH.mint(1 ether);
        vm.stopPrank();
        AccountSnapshot memory snapshot = cBALRETH.getAccountSnapshotPacked(
            user1
        );
        assertEq(snapshot.mTokenBalance, 1 ether);
        assertEq(snapshot.borrowBalance, 0);
        assertEq(snapshot.exchangeRate, 1 ether);

        // try borrow()
        vm.startPrank(user1);
        dDAI.borrow(500 ether);
        vm.stopPrank();
        snapshot = dDAI.getAccountSnapshotPacked(user1);
        assertEq(snapshot.mTokenBalance, 0);
        assertEq(snapshot.borrowBalance, 500 ether);
        assertEq(snapshot.exchangeRate, 1 ether);

        // try borrow()
        skip(1200);
        vm.startPrank(user1);
        dDAI.borrow(100 ether);
        vm.stopPrank();
        snapshot = dDAI.getAccountSnapshotPacked(user1);
        assertEq(snapshot.mTokenBalance, 0);
        assertGt(snapshot.borrowBalance, 600 ether);
        assertGt(snapshot.exchangeRate, 1 ether);

        // skip min hold period
        skip(900);

        // try partial repay
        (, uint256 borrowBalanceBefore, uint256 exchangeRateBefore) = dDAI
            .getAccountSnapshot(user1);
        _prepareDAI(user1, 200 ether);
        vm.startPrank(user1);
        dai.approve(address(dDAI), 200 ether);
        dDAI.repay(200 ether);
        vm.stopPrank();
        snapshot = dDAI.getAccountSnapshotPacked(user1);
        assertEq(snapshot.mTokenBalance, 0);
        assertGt(snapshot.borrowBalance, borrowBalanceBefore - 200 ether);
        assertGt(snapshot.exchangeRate, exchangeRateBefore);

        // skip some period
        skip(1200);

        // try repay full
        (, borrowBalanceBefore, exchangeRateBefore) = dDAI.getAccountSnapshot(
            user1
        );
        _prepareDAI(user1, borrowBalanceBefore);
        vm.startPrank(user1);
        dai.approve(address(dDAI), borrowBalanceBefore);
        dDAI.repay(borrowBalanceBefore);
        vm.stopPrank();
        snapshot = dDAI.getAccountSnapshotPacked(user1);
        assertEq(snapshot.mTokenBalance, 0);
        assertGt(snapshot.borrowBalance, 0);
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
        dDAI.borrow(500 ether);
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
        AccountSnapshot memory snapshot = cBALRETH.getAccountSnapshotPacked(
            user1
        );
        assertEq(snapshot.mTokenBalance, 0.8 ether);
        assertEq(snapshot.borrowBalance, 0 ether);
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
        skip(900);

        // can redeem fully
        vm.startPrank(user1);
        dDAI.redeem(1000 ether);
        vm.stopPrank();

        AccountSnapshot memory snapshot = cBALRETH.getAccountSnapshotPacked(
            user1
        );
        assertEq(snapshot.mTokenBalance, 1 ether);
        assertEq(snapshot.borrowBalance, 0);
        assertEq(snapshot.exchangeRate, 1 ether);

        snapshot = dDAI.getAccountSnapshotPacked(user1);
        assertEq(snapshot.mTokenBalance, 0);
        assertGt(snapshot.borrowBalance, 500 ether);
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
        dDAI.borrow(500 ether);
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
        AccountSnapshot memory snapshot = cBALRETH.getAccountSnapshotPacked(
            user1
        );
        assertEq(snapshot.mTokenBalance, 0.8 ether);
        assertEq(snapshot.borrowBalance, 0 ether);
        assertEq(snapshot.exchangeRate, 1 ether);
        snapshot = cBALRETH.getAccountSnapshotPacked(user2);
        assertEq(snapshot.mTokenBalance, 0.2 ether);
        assertEq(snapshot.borrowBalance, 0 ether);
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
        skip(900);

        // can transefr fully
        vm.startPrank(user1);
        dDAI.transfer(user2, 1000 ether);
        vm.stopPrank();

        AccountSnapshot memory snapshot = cBALRETH.getAccountSnapshotPacked(
            user1
        );
        assertEq(snapshot.mTokenBalance, 1 ether);
        assertEq(snapshot.borrowBalance, 0);
        assertEq(snapshot.exchangeRate, 1 ether);

        snapshot = dDAI.getAccountSnapshotPacked(user1);
        assertEq(snapshot.mTokenBalance, 0);
        assertGt(snapshot.borrowBalance, 500 ether);
        assertGt(snapshot.exchangeRate, 1 ether);

        snapshot = dDAI.getAccountSnapshotPacked(user2);
        assertEq(snapshot.mTokenBalance, 1000 ether);
        assertGt(snapshot.borrowBalance, 0 ether);
        assertGt(snapshot.exchangeRate, 1 ether);
    }

    function testLiquidation() public {
        // testAccountSnapshot
    }
}
