// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { IMToken, AccountSnapshot } from "contracts/interfaces/market/IMToken.sol";
import { MockDataFeed } from "contracts/mocks/MockDataFeed.sol";
import "tests/market/TestBaseMarket.sol";

contract TestNewLiquidationStructure is TestBaseMarket {
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

        // deploy dDAI
        {
            _prepareDAI(owner, 200000e18);
            dai.approve(address(dDAI), 200000e18);
            lendtroller.listToken(address(dDAI));
            // add MToken support on price router
            priceRouter.addMTokenSupport(address(dDAI));
        }

        // deploy CBALRETH
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

    function testLiquidateRevertWhenBelowColReqA() public {
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
        skip(900);

        (uint256 balRETHPrice, ) = priceRouter.getPrice(
            address(balRETH),
            true,
            true
        );

        // adjust dai price, a bit lower than colReqA
        // 1000 dai > 1 cBALRETH / colReqA
        mockDaiFeed.setMockAnswer(
            int256(
                (balRETHPrice * 1 ether * 1e8) / 1000 ether / 1.4 ether - 100
            )
        );

        vm.expectRevert(
            Lendtroller.Lendtroller__NoLiquidationAvailable.selector
        );
        dDAI.liquidateExact(user1, 250 ether, IMToken(address(cBALRETH)));
    }

    function testLiquidateWorksWhenAboveColReqA() public {
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
}
