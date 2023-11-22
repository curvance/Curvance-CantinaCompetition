// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { IMToken } from "contracts/interfaces/market/IMToken.sol";
import { MockDataFeed } from "contracts/mocks/MockDataFeed.sol";

import "tests/market/TestBaseMarket.sol";

contract TestTokenInteractions is TestBaseMarket {
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
        _prepareDAI(liquidityProvider, 200000e18);
        _prepareBALRETH(liquidityProvider, 10 ether);
        // mint dDAI
        vm.startPrank(liquidityProvider);
        dai.approve(address(dDAI), 200000 ether);
        dDAI.mint(200000 ether);
        // mint cBALETH
        balRETH.approve(address(cBALRETH), 10 ether);
        cBALRETH.deposit(10 ether, liquidityProvider);
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
        cBALRETH.deposit(1 ether, user1);
        vm.stopPrank();
        assertEq(cBALRETH.balanceOf(user1), 1 ether);

        // try mintFor()
        vm.startPrank(user1);
        balRETH.approve(address(cBALRETH), 1 ether);
        cBALRETH.deposit(1 ether, user2);
        vm.stopPrank();
        assertEq(cBALRETH.balanceOf(user1), 1 ether);
        assertEq(cBALRETH.balanceOf(user2), 1 ether);

        // try redeem()
        vm.startPrank(user1);
        cBALRETH.redeem(1 ether, user1, user1);
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
        cBALRETH.deposit(1 ether, user1);
        lendtroller.postCollateral(user1, address(cBALRETH), 1 ether);
        vm.stopPrank();

        assertEq(cBALRETH.balanceOf(user1), 1 ether);
        assertEq(cBALRETH.exchangeRateCached(), 1 ether);

        // try borrow()
        vm.startPrank(user1);
        dDAI.borrow(500 ether);
        vm.stopPrank();

        assertEq(dDAI.balanceOf(user1), 0);
        assertEq(dDAI.debtBalanceCached(user1), 500 ether);
        assertEq(dDAI.exchangeRateCached(), 1 ether);

        // try borrow()
        skip(1200);
        vm.startPrank(user1);
        dDAI.borrow(100 ether);
        vm.stopPrank();

        assertEq(dDAI.balanceOf(user1), 0);
        assertGt(dDAI.debtBalanceCached(user1), 600 ether);
        assertGt(dDAI.exchangeRateCached(), 1 ether);

        // skip min hold period
        skip(20 minutes);

        // try partial repay
        uint256 borrowBalanceBefore = dDAI.debtBalanceCached(user1);
        uint256 exchangeRateBefore = dDAI.exchangeRateCached();
        _prepareDAI(user1, 200 ether);
        vm.startPrank(user1);
        dai.approve(address(dDAI), 200 ether);
        dDAI.repay(200 ether);
        vm.stopPrank();

        assertEq(dDAI.balanceOf(user1), 0);
        assertGt(
            dDAI.debtBalanceCached(user1),
            borrowBalanceBefore - 200 ether
        );
        assertGt(dDAI.exchangeRateCached(), exchangeRateBefore);

        // skip some period
        skip(1200);

        // try repay full
        borrowBalanceBefore = dDAI.debtBalanceCached(user1);
        exchangeRateBefore = dDAI.exchangeRateCached();
        _prepareDAI(user1, borrowBalanceBefore);
        vm.startPrank(user1);
        dai.approve(address(dDAI), borrowBalanceBefore);
        dDAI.repay(borrowBalanceBefore);
        vm.stopPrank();

        assertEq(dDAI.balanceOf(user1), 0);
        assertGt(dDAI.debtBalanceCached(user1), 0);
        assertGt(dDAI.exchangeRateCached(), exchangeRateBefore);
    }

    function testCTokenRedeemOnBorrow() public {
        _prepareBALRETH(user1, 1 ether);

        // try mint()
        vm.startPrank(user1);
        balRETH.approve(address(cBALRETH), 1 ether);
        cBALRETH.deposit(1 ether, user1);
        lendtroller.postCollateral(user1, address(cBALRETH), 1 ether);
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
            bytes4(keccak256("Lendtroller__InsufficientCollateral()"))
        );
        cBALRETH.redeem(1 ether, user1, user1);
        vm.stopPrank();

        // can redeem partially
        vm.startPrank(user1);
        cBALRETH.redeem(0.2 ether, user1, user1);
        vm.stopPrank();

        assertEq(cBALRETH.balanceOf(user1), 0.8 ether);
        assertEq(cBALRETH.exchangeRateCached(), 1 ether);
    }

    function testDTokenRedeemOnBorrow() public {
        // try mint()
        _prepareBALRETH(user1, 1 ether);
        vm.startPrank(user1);
        balRETH.approve(address(cBALRETH), 1 ether);
        cBALRETH.deposit(1 ether, user1);
        lendtroller.postCollateral(user1, address(cBALRETH), 1 ether);
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

        assertEq(cBALRETH.balanceOf(user1), 1 ether);
        assertEq(cBALRETH.exchangeRateCached(), 1 ether);

        assertEq(dDAI.balanceOf(user1), 0);
        assertGt(dDAI.debtBalanceCached(user1), 500 ether);
        assertGt(dDAI.exchangeRateCached(), 1 ether);
    }

    function testCTokenTransferOnBorrow() public {
        _prepareBALRETH(user1, 1 ether);

        // try mint()
        vm.startPrank(user1);
        balRETH.approve(address(cBALRETH), 1 ether);
        cBALRETH.deposit(1 ether, user1);
        lendtroller.postCollateral(user1, address(cBALRETH), 1 ether);
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
            bytes4(keccak256("Lendtroller__InsufficientCollateral()"))
        );
        cBALRETH.transfer(user2, 1 ether);
        vm.stopPrank();

        // can redeem partially
        vm.startPrank(user1);
        cBALRETH.transfer(user2, 0.2 ether);
        vm.stopPrank();

        assertEq(cBALRETH.balanceOf(user1), 0.8 ether);
        assertEq(cBALRETH.balanceOf(user2), 0.2 ether);
        assertEq(cBALRETH.exchangeRateCached(), 1 ether);
    }

    function testDTokenTransferOnBorrow() public {
        // try mint()
        _prepareBALRETH(user1, 1 ether);
        vm.startPrank(user1);
        balRETH.approve(address(cBALRETH), 1 ether);
        cBALRETH.deposit(1 ether, user1);
        lendtroller.postCollateral(user1, address(cBALRETH), 1 ether);
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

        assertEq(cBALRETH.balanceOf(user1), 1 ether);
        assertEq(cBALRETH.exchangeRateCached(), 1 ether);

        assertEq(dDAI.balanceOf(user1), 0);
        assertEq(dDAI.debtBalanceCached(user1), 500 ether);

        assertEq(dDAI.balanceOf(user2), 1000 ether);
        assertEq(dDAI.debtBalanceCached(user2), 0 ether);
        assertEq(dDAI.exchangeRateCached(), 1 ether);
    }

    function testLiquidationExact() public {
        _prepareBALRETH(user1, 1 ether);

        // try mint()
        vm.startPrank(user1);
        balRETH.approve(address(cBALRETH), 1 ether);
        cBALRETH.deposit(1 ether, user1);
        lendtroller.postCollateral(user1, address(cBALRETH), 1 ether);
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

        assertApproxEqRel(
            cBALRETH.balanceOf(user1),
            1 ether - (500 ether * 1 ether) / balRETHPrice,
            0.01e18
        );
        assertEq(cBALRETH.exchangeRateCached(), 1 ether);

        assertEq(dDAI.balanceOf(user1), 0);
        assertApproxEqRel(dDAI.debtBalanceCached(user1), 750 ether, 0.01e18);
        assertApproxEqRel(dDAI.exchangeRateCached(), 1 ether, 0.01e18);
    }

    function testLiquidation() public {
        _prepareBALRETH(user1, 1 ether);

        // try mint()
        vm.startPrank(user1);
        balRETH.approve(address(cBALRETH), 1 ether);
        cBALRETH.deposit(1 ether, user1);
        lendtroller.postCollateral(user1, address(cBALRETH), 1 ether);
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

        mockDaiFeed.setMockAnswer(150000000);

        // try liquidate
        _prepareDAI(user2, 10000 ether);
        vm.startPrank(user2);
        dai.approve(address(dDAI), 10000 ether);
        dDAI.liquidate(user1, IMToken(address(cBALRETH)));
        vm.stopPrank();

        assertApproxEqRel(
            cBALRETH.balanceOf(user1),
            1 ether - (1530 ether * 1 ether) / balRETHPrice,
            0.03e18
        );
        assertEq(cBALRETH.exchangeRateCached(), 1 ether);

        assertEq(dDAI.balanceOf(user1), 0);
        assertEq(dDAI.debtBalanceCached(user1), 0);
        assertApproxEqRel(dDAI.exchangeRateCached(), 1 ether, 0.01e18);
    }
}
