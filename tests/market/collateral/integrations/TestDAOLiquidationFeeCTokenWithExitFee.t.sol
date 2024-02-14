// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { MockDataFeed } from "contracts/mocks/MockDataFeed.sol";
import { FixedPointMathLib } from "contracts/libraries/FixedPointMathLib.sol";
import "tests/market/TestBaseMarket.sol";

contract TestCTokenWithExitFeeReserves is TestBaseMarket {
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

        // setup dDAI
        {
            _prepareDAI(owner, 200000e18);
            dai.approve(address(dDAI), 200000e18);
            marketManager.listToken(address(dDAI));
            // add MToken support on price router
            oracleRouter.addMTokenSupport(address(dDAI));
        }

        // setup CBALRETH
        {
            // support market
            _prepareBALRETH(owner, 1 ether);
            balRETH.approve(address(cBALRETHWithExitFee), 1 ether);
            marketManager.listToken(address(cBALRETHWithExitFee));
            // set collateral factor
            marketManager.updateCollateralToken(
                IMToken(address(cBALRETHWithExitFee)),
                7000,
                4000, // liquidate at 71%
                3000,
                200, // 2% liq incentive
                400,
                10,
                1000
            );
            address[] memory tokens = new address[](1);
            tokens[0] = address(cBALRETHWithExitFee);
            uint256[] memory caps = new uint256[](1);
            caps[0] = 100_000e18;
            marketManager.setCTokenCollateralCaps(tokens, caps);
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
        balRETH.approve(address(cBALRETHWithExitFee), 10 ether);
        cBALRETHWithExitFee.deposit(10 ether, liquidityProvider);
        vm.stopPrank();
    }

    function testInitialize() public {
        assertEq(centralRegistry.daoAddress(), dao);
    }

    function testSeizeProtocolFee() public {
        _prepareBALRETH(user1, 1 ether);

        // try mint()
        vm.startPrank(user1);
        balRETH.approve(address(cBALRETHWithExitFee), 1 ether);
        cBALRETHWithExitFee.deposit(1 ether, user1);
        marketManager.postCollateral(
            user1,
            address(cBALRETHWithExitFee),
            1 ether - 1
        );
        vm.stopPrank();

        // try borrow()
        vm.startPrank(user1);
        dDAI.borrow(1000 ether);
        vm.stopPrank();

        // skip min hold period
        skip(20 minutes);

        mockDaiFeed.setMockAnswer(130000000);

        (
            uint256 repayAmount,
            uint256 liquidatedTokens,
            uint256 protocolTokens
        ) = marketManager.canLiquidate(
                address(dDAI),
                address(cBALRETHWithExitFee),
                user1,
                0,
                false
            );
        uint256 daoBalanceBefore = cBALRETHWithExitFee.balanceOf(dao);

        // try liquidate half
        _prepareDAI(user2, repayAmount);
        vm.startPrank(user2);
        dai.approve(address(dDAI), repayAmount);
        dDAI.liquidateExact(
            user1,
            repayAmount,
            IMToken(address(cBALRETHWithExitFee))
        );
        vm.stopPrank();

        assertApproxEqRel(
            cBALRETHWithExitFee.balanceOf(user1),
            1 ether - liquidatedTokens,
            0.01e18
        );
        assertEq(cBALRETHWithExitFee.exchangeRateCached(), 1 ether);

        assertEq(dDAI.balanceOf(user1), 0);
        assertApproxEqRel(
            dDAI.debtBalanceCached(user1),
            1000e18 - repayAmount,
            0.01e18
        );
        assertApproxEqRel(dDAI.exchangeRateCached(), 1 ether, 0.01e18);

        assertApproxEqRel(
            cBALRETHWithExitFee.balanceOf(dao),
            daoBalanceBefore + protocolTokens,
            0.01e18
        );
        assertApproxEqRel(
            gaugePool.balanceOf(address(cBALRETHWithExitFee), dao),
            daoBalanceBefore + protocolTokens,
            0.01e18
        );
    }

    function testDaoCanRedeemProtocolFee() public {
        testSeizeProtocolFee();

        uint256 amountToRedeem = cBALRETHWithExitFee.balanceOf(dao);
        uint256 daoBalanceBefore = balRETH.balanceOf(dao);

        vm.startPrank(dao);
        cBALRETHWithExitFee.redeem(amountToRedeem, dao, dao);
        vm.stopPrank();

        assertEq(cBALRETHWithExitFee.balanceOf(dao), 0);
        assertEq(gaugePool.balanceOf(address(cBALRETHWithExitFee), dao), 0);
        assertEq(
            balRETH.balanceOf(dao),
            daoBalanceBefore +
                amountToRedeem -
                FixedPointMathLib.mulDivUp(
                    cBALRETHWithExitFee.exitFee(),
                    amountToRedeem,
                    1e18
                )
        );
    }

    function testDaoCanTransferProtocolFee() public {
        testSeizeProtocolFee();

        uint256 amountToTransfer = cBALRETHWithExitFee.balanceOf(dao);

        address user = makeAddr("user");
        vm.startPrank(dao);
        cBALRETHWithExitFee.transfer(user, amountToTransfer);
        vm.stopPrank();

        assertEq(cBALRETHWithExitFee.balanceOf(dao), 0);
        assertEq(gaugePool.balanceOf(address(cBALRETHWithExitFee), dao), 0);
        assertEq(cBALRETHWithExitFee.balanceOf(user), amountToTransfer);
        assertEq(
            gaugePool.balanceOf(address(cBALRETHWithExitFee), user),
            amountToTransfer
        );
    }
}
