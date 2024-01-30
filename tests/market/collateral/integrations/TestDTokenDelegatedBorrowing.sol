// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { IMToken, AccountSnapshot } from "contracts/interfaces/market/IMToken.sol";
import { MockDataFeed } from "contracts/mocks/MockDataFeed.sol";
import "tests/market/TestBaseMarket.sol";

contract TestDTokenDelegatedBorrowing is TestBaseMarket {
    address internal constant _UNISWAP_V2_ROUTER =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    address public owner;
    address public dao;

    receive() external payable {}

    fallback() external payable {}

    MockDataFeed public mockDaiFeed;
    MockDataFeed public mockWethFeed;
    MockDataFeed public mockRethFeed;

    function setUp() public override {
        super.setUp();

        owner = address(this);
        dao = address(this);

        // use mock pricing for testing
        mockDaiFeed = new MockDataFeed(_CHAINLINK_DAI_USD);
        chainlinkAdaptor.addAsset(_DAI_ADDRESS, address(mockDaiFeed), 0, true);
        dualChainlinkAdaptor.addAsset(
            _DAI_ADDRESS,
            address(mockDaiFeed),
            0,
            true
        );
        mockWethFeed = new MockDataFeed(_CHAINLINK_ETH_USD);
        chainlinkAdaptor.addAsset(
            _WETH_ADDRESS,
            address(mockWethFeed),
            0,
            true
        );
        dualChainlinkAdaptor.addAsset(
            _WETH_ADDRESS,
            address(mockWethFeed),
            0,
            true
        );
        mockRethFeed = new MockDataFeed(_CHAINLINK_RETH_ETH);
        chainlinkAdaptor.addAsset(
            _RETH_ADDRESS,
            address(mockRethFeed),
            0,
            false
        );
        dualChainlinkAdaptor.addAsset(
            _RETH_ADDRESS,
            address(mockRethFeed),
            0,
            false
        );

        // start epoch
        gaugePool.start(address(marketManager));
        vm.warp(gaugePool.startTime());
        vm.roll(block.number + 1000);

        mockDaiFeed.setMockUpdatedAt(block.timestamp);
        mockWethFeed.setMockUpdatedAt(block.timestamp);
        mockRethFeed.setMockUpdatedAt(block.timestamp);

        (, int256 ethPrice, , , ) = mockWethFeed.latestRoundData();
        chainlinkEthUsd.updateAnswer(ethPrice);

        // deploy dDAI
        {
            // support market
            _prepareDAI(owner, 200000e18);
            dai.approve(address(dDAI), 200000e18);
            marketManager.listToken(address(dDAI));
            // add MToken support on price router
            oracleRouter.addMTokenSupport(address(dDAI));
        }

        // deploy CBALRETH
        {
            // support market
            _prepareBALRETH(owner, 1 ether);
            balRETH.approve(address(cBALRETH), 1 ether);
            marketManager.listToken(address(cBALRETH));
            // set collateral factor
            marketManager.updateCollateralToken(
                IMToken(address(cBALRETH)),
                5000,
                1500,
                1200,
                200,
                400,
                10,
                1000
            );
            address[] memory tokens = new address[](1);
            tokens[0] = address(cBALRETH);
            uint256[] memory caps = new uint256[](1);
            caps[0] = 100_000e18;
            marketManager.setCTokenCollateralCaps(tokens, caps);
        }

        centralRegistry.addSwapper(_UNISWAP_V2_ROUTER);
    }

    function testInitialize() public {
        assertEq(centralRegistry.daoAddress(), dao);
        assertEq(dDAI.interestFactor(), (marketInterestFactor * 1e18) / 10000);
        assertEq(
            dDAI.interestFactor(),
            centralRegistry.protocolInterestFactor(address(marketManager))
        );
    }

    function testDelegatedBorrowing() public {
        address liquidityProvider = makeAddr("liquidityProvider");
        _prepareDAI(liquidityProvider, 1000 ether);
        _prepareBALRETH(liquidityProvider, 10 ether);
        // mint dDAI
        vm.startPrank(liquidityProvider);
        dai.approve(address(dDAI), 1000 ether);
        dDAI.mint(1000 ether);

        _prepareBALRETH(user1, 1 ether);

        // try mint()
        vm.startPrank(user1);
        balRETH.approve(address(cBALRETH), 1 ether);
        cBALRETH.deposit(1 ether, user1);
        marketManager.postCollateral(user1, address(cBALRETH), 1 ether - 1);

        // delegate borrow
        dDAI.setBorrowApproval(user2, true);
        vm.stopPrank();

        // try borrow()
        vm.startPrank(user2);
        dDAI.borrowFor(user1, user2, 500 ether);
        vm.stopPrank();

        assertEq(dai.balanceOf(user1), 0);
        assertEq(dai.balanceOf(user2), 500 ether);

        {
            // check accrue interest after 1 day
            uint256 exchangeRateBefore = dDAI.exchangeRateCached();
            uint256 totalReserves = dDAI.totalReserves();
            assertEq(totalReserves, 0);
            uint256 totalBorrowsBefore = dDAI.totalBorrows();
            assertEq(totalBorrowsBefore, 500 ether);
            uint256 daoBalanceBefore = dDAI.balanceOf(dao);
            uint256 daoGaugeBalanceBefore = gaugePool.balanceOf(
                address(dDAI),
                dao
            );
            uint256 debtBalanceBefore = dDAI.debtBalanceCached(user1);

            // skip 1 day
            skip(24 hours);

            dDAI.accrueInterest();

            uint256 debt = dDAI.totalBorrows() - totalBorrowsBefore;

            // check interest calculation from debt accrued
            assertEq(
                dDAI.totalReserves(),
                totalReserves + (debt * marketInterestFactor) / 10000
            );

            // check borrower debt increased
            assertEq(dDAI.balanceOf(user1), 0);
            assertEq(dDAI.debtBalanceCached(user1), debtBalanceBefore + debt);
            assertGt(dDAI.exchangeRateCached(), exchangeRateBefore);

            // dao dDAI balance doesn't increase
            assertEq(dDAI.balanceOf(dao), daoBalanceBefore);

            // check gauge balance
            assertEq(
                gaugePool.balanceOf(address(dDAI), dao),
                daoGaugeBalanceBefore + (debt * marketInterestFactor) / 10000
            );
        }

        {
            // check accrue interest after another day
            uint256 exchangeRateBefore = dDAI.exchangeRateCached();
            uint256 totalReserves = dDAI.totalReserves();
            uint256 totalBorrowsBefore = dDAI.totalBorrows();
            uint256 daoBalanceBefore = dDAI.balanceOf(dao);
            uint256 daoGaugeBalanceBefore = gaugePool.balanceOf(
                address(dDAI),
                dao
            );
            uint256 debtBalanceBefore = dDAI.debtBalanceCached(user1);

            // skip 1 day
            skip(24 hours);

            dDAI.accrueInterest();

            uint256 debt = dDAI.totalBorrows() - totalBorrowsBefore;

            // check interest calculation from debt accrued
            assertEq(
                dDAI.totalReserves(),
                totalReserves + (debt * marketInterestFactor) / 10000
            );

            // check borrower debt increased
            assertEq(dDAI.balanceOf(user1), 0);
            assertApproxEqRel(
                dDAI.debtBalanceCached(user1),
                debtBalanceBefore + debt,
                10000
            );
            assertGt(dDAI.exchangeRateCached(), exchangeRateBefore);

            // dao dDAI balance doesn't increase
            assertEq(dDAI.balanceOf(dao), daoBalanceBefore);

            // check gauge balance
            assertEq(
                gaugePool.balanceOf(address(dDAI), dao),
                daoGaugeBalanceBefore + (debt * marketInterestFactor) / 10000
            );
        }
    }
}
