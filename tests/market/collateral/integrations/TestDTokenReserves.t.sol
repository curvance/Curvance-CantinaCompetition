// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { IMToken, AccountSnapshot } from "contracts/interfaces/market/IMToken.sol";
import { MockDataFeed } from "contracts/mocks/MockDataFeed.sol";

import "tests/market/TestBaseMarket.sol";

contract TestDTokenReserves is TestBaseMarket {
    address internal constant _UNISWAP_V2_ROUTER =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    address public owner;
    address public dao;

    receive() external payable {}

    fallback() external payable {}

    MockDataFeed public mockDaiFeed;

    function setUp() public override {
        super.setUp();

        owner = address(this);
        dao = address(this);

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
                2000,
                500,
                5000
            );
            address[] memory markets = new address[](1);
            markets[0] = address(cBALRETH);
            vm.prank(user1);
            lendtroller.enterMarkets(markets);
            vm.prank(user2);
            lendtroller.enterMarkets(markets);
        }

        centralRegistry.addSwapper(_UNISWAP_V2_ROUTER);

        // use mock pricing for testing
        mockDaiFeed = new MockDataFeed(_CHAINLINK_DAI_USD);
        chainlinkAdaptor.addAsset(_DAI_ADDRESS, address(mockDaiFeed), true);
        dualChainlinkAdaptor.addAsset(
            _DAI_ADDRESS,
            address(mockDaiFeed),
            true
        );
    }

    function testInitialize() public {
        assertEq(centralRegistry.daoAddress(), dao);
        assertEq(dDAI.interestFactor(), (marketInterestFactor * 1e18) / 10000);
        assertEq(
            dDAI.interestFactor(),
            centralRegistry.protocolInterestFactor(address(lendtroller))
        );
    }

    function testDaoInterestFromDToken() public {
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
        cBALRETH.mint(1 ether);
        vm.stopPrank();

        // try borrow()
        vm.startPrank(user1);
        dDAI.borrow(500 ether);
        vm.stopPrank();

        {
            // check accrue interest after 1 day
            uint256 exchangeRateBefore = dDAI.exchangeRateStored();
            uint256 totalReserves = dDAI.totalReserves();
            assertEq(totalReserves, 0);
            uint256 totalBorrowsBefore = dDAI.totalBorrows();
            assertEq(totalBorrowsBefore, 500 ether);
            uint256 daoBalanceBefore = dDAI.balanceOf(dao);
            uint256 daoGaugeBalanceBefore = gaugePool.balanceOf(
                address(dDAI),
                dao
            );
            uint256 debtBalanceBefore = dDAI.borrowBalanceStored(user1);

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
            AccountSnapshot memory snapshot = dDAI.getSnapshotPacked(
                user1
            );
            assertEq(snapshot.balance, 0);
            assertEq(snapshot.debtBalance, debtBalanceBefore + debt);
            assertGt(snapshot.exchangeRate, exchangeRateBefore);

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
            uint256 exchangeRateBefore = dDAI.exchangeRateStored();
            uint256 totalReserves = dDAI.totalReserves();
            uint256 totalBorrowsBefore = dDAI.totalBorrows();
            uint256 daoBalanceBefore = dDAI.balanceOf(dao);
            uint256 daoGaugeBalanceBefore = gaugePool.balanceOf(
                address(dDAI),
                dao
            );
            uint256 debtBalanceBefore = dDAI.borrowBalanceStored(user1);

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
            AccountSnapshot memory snapshot = dDAI.getSnapshotPacked(
                user1
            );
            assertEq(snapshot.balance, 0);
            assertApproxEqRel(
                snapshot.borrowBalance,
                debtBalanceBefore + debt,
                10000
            );
            assertGt(snapshot.exchangeRate, exchangeRateBefore);

            // dao dDAI balance doesn't increase
            assertEq(dDAI.balanceOf(dao), daoBalanceBefore);

            // check gauge balance
            assertEq(
                gaugePool.balanceOf(address(dDAI), dao),
                daoGaugeBalanceBefore + (debt * marketInterestFactor) / 10000
            );
        }
    }

    function testDaoDepositReserves() public {
        testDaoInterestFromDToken();

        uint256 exchangeRate = dDAI.exchangeRateStored();
        uint256 totalReservesBefore = dDAI.totalReserves();
        uint256 gaugeBalanceBefore = gaugePool.balanceOf(address(dDAI), dao);

        uint256 depositAmount = 100 ether;
        _prepareDAI(dao, depositAmount);
        vm.startPrank(dao);
        dai.approve(address(dDAI), depositAmount);
        dDAI.depositReserves(depositAmount);
        vm.stopPrank();

        assertEq(
            dDAI.totalReserves(),
            totalReservesBefore + (depositAmount * 1e18) / exchangeRate
        );
        assertEq(
            gaugePool.balanceOf(address(dDAI), dao),
            gaugeBalanceBefore + (depositAmount * 1e18) / exchangeRate
        );
    }

    function testDaoWithdrawReserves() public {
        testDaoDepositReserves();

        {
            // withdraw half
            uint256 exchangeRate = dDAI.exchangeRateStored();
            uint256 totalReservesBefore = dDAI.totalReserves();
            uint256 daiBalanceBefore = dai.balanceOf(dao);
            uint256 gaugeBalanceBefore = gaugePool.balanceOf(
                address(dDAI),
                dao
            );

            uint256 withdrawAmount = ((totalReservesBefore / 2) *
                exchangeRate) / 1e18;
            vm.startPrank(dao);
            dDAI.withdrawReserves(withdrawAmount);
            vm.stopPrank();

            assertEq(
                dDAI.totalReserves(),
                totalReservesBefore - ((withdrawAmount * 1e18) / exchangeRate)
            );
            assertEq(
                gaugePool.balanceOf(address(dDAI), dao),
                gaugeBalanceBefore - ((withdrawAmount * 1e18) / exchangeRate)
            );
            assertEq(dai.balanceOf(dao), daiBalanceBefore + withdrawAmount);
        }

        {
            // withdraw half
            uint256 exchangeRate = dDAI.exchangeRateStored();
            uint256 totalReservesBefore = dDAI.totalReserves();
            uint256 daiBalanceBefore = dai.balanceOf(dao);

            uint256 withdrawAmount = ((totalReservesBefore) * exchangeRate) /
                1e18;
            if ((withdrawAmount * 1e18) / exchangeRate < totalReservesBefore) {
                withdrawAmount += 1;
            }
            vm.startPrank(dao);
            dDAI.withdrawReserves(withdrawAmount);
            vm.stopPrank();

            assertEq(dDAI.totalReserves(), 0);
            assertEq(gaugePool.balanceOf(address(dDAI), dao), 42069);
            assertEq(dai.balanceOf(dao), daiBalanceBefore + withdrawAmount);
        }
    }
}
