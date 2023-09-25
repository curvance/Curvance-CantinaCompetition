// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { IMToken, AccountSnapshot } from "contracts/interfaces/market/IMToken.sol";
import { IUniswapV2Router } from "contracts/interfaces/external/uniswap/IUniswapV2Router.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { MockDataFeed } from "contracts/mocks/MockDataFeed.sol";

import "tests/market/TestBaseMarket.sol";

contract User {}

contract TestCTokenReserves is TestBaseMarket {
    address internal constant _UNISWAP_V2_ROUTER =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    address public owner;

    receive() external payable {}

    fallback() external payable {}

    MockDataFeed public mockDaiFeed;

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

        // provide enough liquidity
        provideEnoughLiquidityForLeverage();

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
        assertEq(centralRegistry.daoAddress(), address(this));
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
        dDAI.borrow(500 ether);
        vm.stopPrank();

        // skip min hold period
        skip(900);

        (uint256 balRETHPrice, ) = priceRouter.getPrice(
            address(balRETH),
            true,
            true
        );

        mockDaiFeed.setMockAnswer(200000000);

        uint256 repayAmount = 250 ether;
        (uint256 liquidatedTokens, uint256 protocolTokens) = lendtroller
            .calculateLiquidatedTokens(
                address(dDAI),
                address(cBALRETH),
                repayAmount
            );
        uint256 daoBalanceBefore = cBALRETH.balanceOf(address(this));

        // try liquidate half
        _prepareDAI(user2, repayAmount);
        vm.startPrank(user2);
        dai.approve(address(dDAI), repayAmount);
        dDAI.liquidate(user1, repayAmount, IMToken(address(cBALRETH)));
        vm.stopPrank();

        AccountSnapshot memory snapshot = cBALRETH.getAccountSnapshotPacked(
            user1
        );
        assertApproxEqRel(
            snapshot.mTokenBalance,
            1 ether - liquidatedTokens,
            0.01e18
        );
        assertEq(snapshot.borrowBalance, 0);
        assertEq(snapshot.exchangeRate, 1 ether);

        snapshot = dDAI.getAccountSnapshotPacked(user1);
        assertEq(snapshot.mTokenBalance, 0);
        assertApproxEqRel(snapshot.borrowBalance, 250 ether, 0.01e18);
        assertApproxEqRel(snapshot.exchangeRate, 1 ether, 0.01e18);

        assertEq(
            cBALRETH.balanceOf(address(this)),
            daoBalanceBefore + protocolTokens
        );
    }
}
