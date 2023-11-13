// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { IMToken, AccountSnapshot } from "contracts/interfaces/market/IMToken.sol";
import { MockDataFeed } from "contracts/mocks/MockDataFeed.sol";

import "tests/market/TestBaseMarket.sol";

contract TestCTokenReserves is TestBaseMarket {
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

        // deploy dDAI
        {
            _deployDDAI();
            // support market
            _prepareDAI(owner, 200000e18);
            dai.approve(address(dDAI), 200000e18);
            lendtroller.listToken(address(dDAI));
            // add MToken support on price router
            priceRouter.addMTokenSupport(address(dDAI));
            address[] memory markets = new address[](1);
            markets[0] = address(dDAI);
            vm.prank(user1);
            // lendtroller.enterMarkets(markets);
            vm.prank(user2);
            // lendtroller.enterMarkets(markets);
        }

        // deploy CBALRETH
        {
            // deploy aura position vault
            _deployCBALRETH();

            // support market
            _prepareBALRETH(owner, 1 ether);
            balRETH.approve(address(cBALRETH), 1 ether);
            lendtroller.listToken(address(cBALRETH));
            // add MToken support on price router
            priceRouter.addMTokenSupport(address(cBALRETH));
            // set collateral factor
            lendtroller.updateCollateralToken(
                IMToken(address(cBALRETH)),
                7000,
                4000, // liquidate at 71%
                3000,
                200,
                400,
                100,
                200
            );
            address[] memory markets = new address[](1);
            markets[0] = address(cBALRETH);
            vm.prank(user1);
            // lendtroller.enterMarkets(markets);
            vm.prank(user2);
            // lendtroller.enterMarkets(markets);
        }

        // provide enough liquidity
        provideEnoughLiquidityForLeverage();

        centralRegistry.addSwapper(_UNISWAP_V2_ROUTER);
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
        assertEq(centralRegistry.daoAddress(), dao);
    }

    function testSeizeProtocolFee() public {
        _prepareBALRETH(user1, 1 ether);

        // try mint()
        vm.startPrank(user1);
        balRETH.approve(address(cBALRETH), 1 ether);
        cBALRETH.mint(1 ether);
        vm.stopPrank();

        // try borrow()
        vm.startPrank(user1);
        dDAI.borrow(1000 ether);
        vm.stopPrank();

        // skip min hold period
        skip(900);

        mockDaiFeed.setMockAnswer(200000000);

        uint256 repayAmount = 250 ether;
        (, uint256 liquidatedTokens, uint256 protocolTokens) = lendtroller
            .canLiquidateWithExecution(
                address(dDAI),
                address(cBALRETH),
                user1,
                repayAmount,
                true
            );
        uint256 daoBalanceBefore = cBALRETH.balanceOf(dao);

        // try liquidate half
        _prepareDAI(user2, repayAmount);
        vm.startPrank(user2);
        dai.approve(address(dDAI), repayAmount);
        dDAI.liquidateExact(user1, repayAmount, IMToken(address(cBALRETH)));
        vm.stopPrank();

        AccountSnapshot memory snapshot = cBALRETH.getSnapshotPacked(user1);
        assertApproxEqRel(
            cBALRETH.balanceOf(user1),
            1 ether - liquidatedTokens,
            0.01e18
        );
        assertEq(snapshot.debtBalance, 0);
        assertEq(snapshot.exchangeRate, 1 ether);

        snapshot = dDAI.getSnapshotPacked(user1);
        // assertEq(snapshot.balance, 0);
        assertApproxEqRel(snapshot.debtBalance, 750 ether, 0.01e18);
        assertApproxEqRel(snapshot.exchangeRate, 1 ether, 0.01e18);

        assertEq(cBALRETH.balanceOf(dao), daoBalanceBefore + protocolTokens);
        assertEq(
            gaugePool.balanceOf(address(cBALRETH), dao),
            daoBalanceBefore + protocolTokens
        );
    }

    function testDaoCanRedeemProtocolFee() public {
        testSeizeProtocolFee();

        uint256 amountToRedeem = cBALRETH.balanceOf(dao);
        uint256 daoBalanceBefore = balRETH.balanceOf(dao);

        vm.startPrank(dao);
        cBALRETH.redeem(amountToRedeem);
        vm.stopPrank();

        assertEq(cBALRETH.balanceOf(dao), 0);
        assertEq(gaugePool.balanceOf(address(cBALRETH), dao), 0);
        assertEq(balRETH.balanceOf(dao), daoBalanceBefore + amountToRedeem);
    }

    function testDaoCanTransferProtocolFee() public {
        testSeizeProtocolFee();

        uint256 amountToTransfer = cBALRETH.balanceOf(dao);

        address user = makeAddr("user");
        vm.startPrank(dao);
        cBALRETH.transferFrom(dao, user, amountToTransfer);
        vm.stopPrank();

        assertEq(cBALRETH.balanceOf(dao), 0);
        assertEq(gaugePool.balanceOf(address(cBALRETH), dao), 0);
        assertEq(cBALRETH.balanceOf(user), amountToTransfer);
        assertEq(
            gaugePool.balanceOf(address(cBALRETH), user),
            amountToTransfer
        );
    }
}
