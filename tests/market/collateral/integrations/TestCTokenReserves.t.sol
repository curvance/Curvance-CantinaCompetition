// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

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
                4000, // liquidate at 71%
                3000,
                200, // 2% liq incentive
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
        cBALRETH.deposit(10 ether, liquidityProvider);
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
        cBALRETH.deposit(1 ether, user1);
        lendtroller.postCollateral(user1, address(cBALRETH), 1 ether - 1);
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
        ) = lendtroller.canLiquidate(
                address(dDAI),
                address(cBALRETH),
                user1,
                0,
                false
            );
        uint256 daoBalanceBefore = cBALRETH.balanceOf(dao);

        // try liquidate half
        _prepareDAI(user2, repayAmount);
        vm.startPrank(user2);
        dai.approve(address(dDAI), repayAmount);
        dDAI.liquidateExact(user1, repayAmount, IMToken(address(cBALRETH)));
        vm.stopPrank();

        assertApproxEqRel(
            cBALRETH.balanceOf(user1),
            1 ether - liquidatedTokens,
            0.01e18
        );
        assertEq(cBALRETH.exchangeRateCached(), 1 ether);

        assertEq(dDAI.balanceOf(user1), 0);
        assertApproxEqRel(
            dDAI.debtBalanceCached(user1),
            1000e18 - repayAmount,
            0.01e18
        );
        assertApproxEqRel(dDAI.exchangeRateCached(), 1 ether, 0.01e18);

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
        cBALRETH.redeem(amountToRedeem, dao, dao);
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
        cBALRETH.transfer(user, amountToTransfer);
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
