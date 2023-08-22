// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { IMToken } from "contracts/interfaces/market/IMToken.sol";

import "tests/market/TestBaseMarket.sol";

contract User {}

contract TestPositionFolding is TestBaseMarket {
    address internal constant _UNISWAP_V2_ROUTER =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    address public owner;
    address public user;

    receive() external payable {}

    fallback() external payable {}

    function setUp() public override {
        super.setUp();

        owner = address(this);
        user = user1;

        _prepareUSDC(user, 200000e6);
        _prepareDAI(user, 200000e18);
        _prepareBALRETH(user, 1 ether);

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
            vm.prank(user);
            address[] memory markets = new address[](1);
            markets[0] = address(dDAI);
            lendtroller.enterMarkets(markets);
            // approve
            vm.prank(user);
            dai.approve(address(dDAI), 200000e18);
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
            lendtroller.setCollateralizationRatio(
                IMToken(address(cBALRETH)),
                5e17
            );
            vm.prank(user);
            address[] memory markets = new address[](1);
            markets[0] = address(cBALRETH);
            lendtroller.enterMarkets(markets);
            // approve
            vm.prank(user);
            dai.approve(address(cBALRETH), 200000e18);
        }

        // set position folding
        Lendtroller(lendtroller).setPositionFolding(address(positionFolding));

        vm.warp(gaugePool.startTime());
        vm.roll(block.number + 1000);

        // set gauge settings of next epoch
        address[] memory tokensParam = new address[](2);
        tokensParam[0] = address(dDAI);
        tokensParam[1] = address(cBALRETH);
        uint256[] memory poolWeights = new uint256[](2);
        poolWeights[0] = 100;
        poolWeights[1] = 100;
        vm.prank(protocolMessagingHub);
        gaugePool.setEmissionRates(1, tokensParam, poolWeights);
        vm.prank(protocolMessagingHub);
        cve.mintGaugeEmissions(300 * 2 weeks, address(gaugePool));
        vm.warp(gaugePool.startTime() + 1 * 2 weeks);

        // provide enough liquidity for leverage
        provideEnoughLiquidityForLeverage();
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
        assertEq(
            address(positionFolding.centralRegistry()),
            address(centralRegistry)
        );
        assertEq(address(positionFolding.lendtroller()), address(lendtroller));
    }

    // function testLeverageMaxWithOnlyCToken() public {
    //     vm.startPrank(user);

    //     // enter markets
    //     _enterCDAIMarket(user);

    //     // approve
    //     dai.approve(address(cDAI), 100 ether);

    //     // mint
    //     assertTrue(cDAI.mint(100 ether));
    //     assertEq(cDAI.balanceOf(user), 100 ether);

    //     uint256 balanceBeforeBorrow = dai.balanceOf(user);
    //     // borrow
    //     cDAI.borrow(25 ether);
    //     assertEq(cDAI.balanceOf(user), 100 ether);
    //     assertEq(balanceBeforeBorrow + 25 ether, dai.balanceOf(user));

    //     assertEq(
    //         positionFolding.queryAmountToBorrowForLeverageMax(
    //             user,
    //             CToken(address(cDAI))
    //         ),
    //         172 ether
    //     );
    //     positionFolding.leverageMax(
    //         CToken(address(cDAI)),
    //         CToken(address(cDAI)),
    //         PositionFolding.Swap({ target: address(0), call: "0x" }),
    //         3000
    //     );

    //     (uint256 cTokenBalance, uint256 borrowBalance, ) = cDAI
    //         .getAccountSnapshot(user);
    //     assertEq(cTokenBalance, 272 ether);
    //     assertEq(borrowBalance, 197 ether);

    //     vm.stopPrank();
    // }

    // function testDeLeverageWithOnlyCToken() public {
    //     vm.startPrank(user);

    //     // enter markets
    //     _enterCDAIMarket(user);

    //     // approve
    //     dai.approve(address(cDAI), 100 ether);

    //     // mint
    //     assertTrue(cDAI.mint(100 ether));
    //     assertEq(cDAI.balanceOf(user), 100 ether);

    //     uint256 balanceBeforeBorrow = dai.balanceOf(user);
    //     // borrow
    //     cDAI.borrow(25 ether);
    //     assertEq(cDAI.balanceOf(user), 100 ether);
    //     assertEq(balanceBeforeBorrow + 25 ether, dai.balanceOf(user));

    //     assertEq(
    //         positionFolding.queryAmountToBorrowForLeverageMax(
    //             user,
    //             CToken(address(cDAI))
    //         ),
    //         172 ether
    //     );
    //     positionFolding.leverageMax(
    //         CToken(address(cDAI)),
    //         CToken(address(cDAI)),
    //         PositionFolding.Swap({ target: address(0), call: "0x" }),
    //         3000
    //     );

    //     (uint256 cTokenBalance, uint256 borrowBalance, ) = cDAI
    //         .getAccountSnapshot(user);
    //     assertEq(cTokenBalance, 272 ether);
    //     assertEq(borrowBalance, 197 ether);

    //     positionFolding.deleverage(
    //         CToken(address(cDAI)),
    //         197 ether,
    //         CToken(address(cDAI)),
    //         197 ether,
    //         PositionFolding.Swap({ target: address(0), call: "0x" }),
    //         3000
    //     );

    //     (cTokenBalance, borrowBalance, ) = cDAI.getAccountSnapshot(user);
    //     assertEq(cTokenBalance, 75 ether);
    //     assertEq(borrowBalance, 0 ether);

    //     vm.stopPrank();
    // }

    // function testLeverageMaxWithOnlyCEther() public {
    //     vm.startPrank(user);

    //     // enter markets
    //     _enterCEtherMarket(user);

    //     // mint
    //     cETH.mint{ value: 100 ether }();
    //     assertEq(cETH.balanceOf(user), 100 ether);

    //     uint256 balanceBeforeBorrow = user.balance;
    //     // borrow
    //     cETH.borrow(25 ether);
    //     assertEq(cETH.balanceOf(user), 100 ether);
    //     assertEq(balanceBeforeBorrow + 25 ether, user.balance);

    //     assertEq(
    //         positionFolding.queryAmountToBorrowForLeverageMax(
    //             user,
    //             CToken(address(cETH))
    //         ),
    //         172 ether
    //     );
    //     positionFolding.leverageMax(
    //         CToken(address(cETH)),
    //         CToken(address(cETH)),
    //         PositionFolding.Swap({ target: address(0), call: "0x" }),
    //         3000
    //     );

    //     (uint256 cTokenBalance, uint256 borrowBalance, ) = cETH
    //         .getAccountSnapshot(user);
    //     assertEq(cTokenBalance, 272 ether);
    //     assertEq(borrowBalance, 197 ether);

    //     vm.stopPrank();
    // }

    // function testDeLeverageWithOnlyCEther() public {
    //     vm.startPrank(user);

    //     // enter markets
    //     _enterCEtherMarket(user);

    //     // mint
    //     cETH.mint{ value: 100 ether }();
    //     assertEq(cETH.balanceOf(user), 100 ether);

    //     uint256 balanceBeforeBorrow = user.balance;
    //     // borrow
    //     cETH.borrow(25 ether);
    //     assertEq(cETH.balanceOf(user), 100 ether);
    //     assertEq(balanceBeforeBorrow + 25 ether, user.balance);

    //     assertEq(
    //         positionFolding.queryAmountToBorrowForLeverageMax(
    //             user,
    //             CToken(address(cETH))
    //         ),
    //         172 ether
    //     );
    //     positionFolding.leverageMax(
    //         CToken(address(cETH)),
    //         CToken(address(cETH)),
    //         PositionFolding.Swap({ target: address(0), call: "0x" }),
    //         3000
    //     );

    //     (uint256 cTokenBalance, uint256 borrowBalance, ) = cETH
    //         .getAccountSnapshot(user);
    //     assertEq(cTokenBalance, 272 ether);
    //     assertEq(borrowBalance, 197 ether);

    //     positionFolding.deleverage(
    //         CToken(address(cETH)),
    //         197 ether,
    //         CToken(address(cETH)),
    //         197 ether,
    //         PositionFolding.Swap({ target: address(0), call: "0x" }),
    //         3000
    //     );

    //     (cTokenBalance, borrowBalance, ) = cETH.getAccountSnapshot(user);
    //     assertEq(cTokenBalance, 75 ether);
    //     assertEq(borrowBalance, 0 ether);

    //     vm.stopPrank();
    // }

    // function testLeverageMaxIntegration1() public {
    //     vm.startPrank(user);

    //     // enter markets
    //     _enterMarkets(user);

    //     // mint 2000 DAI_ADDRESS
    //     dai.approve(address(cDAI), 2000 ether);
    //     cDAI.mint(2000 ether);

    //     // mint 1 ether
    //     cETH.mint{ value: _ONE }();

    //     // borrow 500 DAI_ADDRESS
    //     cDAI.borrow(500 ether);

    //     // borrow 0.25 ether
    //     cETH.borrow(0.25 ether);

    //     uint256 amountForLeverage = positionFolding
    //         .queryAmountToBorrowForLeverageMax(user, CToken(address(cDAI)));
    //     assertEq(amountForLeverage, 6880 ether);

    //     address[] memory path = new address[](2);
    //     path[0] = DAI_ADDRESS;
    //     path[1] = _WETH_ADDRESS;
    //     positionFolding.leverageMax(
    //         CToken(address(cDAI)),
    //         CToken(address(cETH)),
    //         PositionFolding.Swap({
    //             target: _UNISWAP_V2_ROUTER,
    //             call: abi.encodeWithSignature(
    //                 "swapExactTokensForETH(uint256,uint256,address[],address,uint256)",
    //                 amountForLeverage,
    //                 0,
    //                 path,
    //                 address(positionFolding),
    //                 block.timestamp
    //             )
    //         }),
    //         3000
    //     );

    //     (uint256 cDAIBalance, uint256 daiBorrowBalance, ) = cDAI
    //         .getAccountSnapshot(user);
    //     (uint256 cETHBalance, uint256 ethBorrowBalance, ) = cETH
    //         .getAccountSnapshot(user);
    //     assertEq(cDAIBalance, 2000 ether); // $2000
    //     assertGt(cETHBalance, 3.7 ether); // $7400
    //     assertEq(daiBorrowBalance, 7380 ether); // $7380
    //     assertEq(ethBorrowBalance, 0.25 ether); // $500

    //     (
    //         uint256 sumCollateral,
    //         uint256 maxBorrow,
    //         uint256 sumBorrow
    //     ) = Lendtroller(lendtroller).getAccountPosition(user);
    //     assertGt(sumCollateral, 9400 ether);
    //     assertGt(maxBorrow, (9400 ether * 75) / 100);
    //     assertEq(sumBorrow, 7880 ether);

    //     vm.stopPrank();
    // }

    // function testDeLeverageIntegration1() public {
    //     vm.startPrank(user);

    //     _enterMarkets(user);

    //     // mint 2000 DAI_ADDRESS
    //     dai.approve(address(cDAI), 2000 ether);
    //     cDAI.mint(2000 ether);

    //     // mint 1 ether
    //     cETH.mint{ value: _ONE }();

    //     // borrow 500 DAI_ADDRESS
    //     cDAI.borrow(500 ether);

    //     // borrow 0.25 ether
    //     cETH.borrow(0.25 ether);

    //     {
    //         uint256 amountForLeverage = positionFolding
    //             .queryAmountToBorrowForLeverageMax(
    //                 user,
    //                 CToken(address(cDAI))
    //             );
    //         assertEq(amountForLeverage, 6880 ether);

    //         address[] memory path = new address[](2);
    //         path[0] = DAI_ADDRESS;
    //         path[1] = _WETH_ADDRESS;

    //         positionFolding.leverageMax(
    //             CToken(address(cDAI)),
    //             CToken(address(cETH)),
    //             PositionFolding.Swap({
    //                 target: _UNISWAP_V2_ROUTER,
    //                 call: abi.encodeWithSignature(
    //                     "swapExactTokensForETH(uint256,uint256,address[],address,uint256)",
    //                     amountForLeverage,
    //                     0,
    //                     path,
    //                     address(positionFolding),
    //                     block.timestamp
    //                 )
    //             }),
    //             3000
    //         );
    //     }

    //     {
    //         (uint256 cDAIBalance, uint256 daiBorrowBalance, ) = cDAI
    //             .getAccountSnapshot(user);
    //         (uint256 cETHBalance, uint256 ethBorrowBalance, ) = cETH
    //             .getAccountSnapshot(user);
    //         assertEq(cDAIBalance, 2000 ether); // $2000
    //         assertGt(cETHBalance, 3.7 ether); // $7400
    //         assertEq(daiBorrowBalance, 7380 ether); // $7380
    //         assertEq(ethBorrowBalance, 0.25 ether); // $500

    //         (
    //             uint256 sumCollateral,
    //             uint256 maxBorrow,
    //             uint256 sumBorrow
    //         ) = Lendtroller(lendtroller).getAccountPosition(user);
    //         assertGt(sumCollateral, 9400 ether);
    //         assertGt(maxBorrow, (9400 ether * 75) / 100);
    //         assertEq(sumBorrow, 7880 ether);
    //     }

    //     {
    //         address[] memory path = new address[](2);
    //         path[0] = _WETH_ADDRESS;
    //         path[1] = DAI_ADDRESS;
    //         positionFolding.deleverage(
    //             CToken(address(cETH)),
    //             3.7 ether,
    //             CToken(address(cDAI)),
    //             6300 ether,
    //             PositionFolding.Swap({
    //                 target: _UNISWAP_V2_ROUTER,
    //                 call: abi.encodeWithSignature(
    //                     "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)",
    //                     3.7 ether,
    //                     0,
    //                     path,
    //                     address(positionFolding),
    //                     block.timestamp
    //                 )
    //             }),
    //             3000
    //         );
    //     }

    //     {
    //         (uint256 cDAIBalance, uint256 daiBorrowBalance, ) = cDAI
    //             .getAccountSnapshot(user);
    //         (uint256 cETHBalance, uint256 ethBorrowBalance, ) = cETH
    //             .getAccountSnapshot(user);
    //         assertGt(cDAIBalance, 2000 ether); // $2000
    //         assertGt(cETHBalance, 0 ether); // $7400
    //         assertEq(daiBorrowBalance, 1080 ether);
    //         assertEq(ethBorrowBalance, 0.25 ether); // $500

    //         (
    //             uint256 sumCollateral,
    //             uint256 maxBorrow,
    //             uint256 sumBorrow
    //         ) = Lendtroller(lendtroller).getAccountPosition(user);
    //         assertGt(sumCollateral, 2000 ether);
    //         assertGt(maxBorrow, (2000 ether * 75) / 100);
    //         assertEq(sumBorrow, 1580 ether);
    //     }

    //     vm.stopPrank();
    // }

    // function testLeverageMaxCheckAccountHealthy() public {
    //     vm.startPrank(user);

    //     // enter markets
    //     _enterMarkets(user);

    //     // mint 2000 DAI_ADDRESS
    //     dai.approve(address(cDAI), 2000 ether);
    //     cDAI.mint(2000 ether);

    //     // mint 1 ether
    //     cETH.mint{ value: _ONE }();

    //     // borrow 500 DAI_ADDRESS
    //     cDAI.borrow(500 ether);

    //     // borrow 0.25 ether
    //     cETH.borrow(0.25 ether);

    //     uint256 amountForLeverage = positionFolding
    //         .queryAmountToBorrowForLeverageMax(user, CToken(address(cDAI)));
    //     assertEq(amountForLeverage, 6880 ether);

    //     address[] memory path = new address[](2);
    //     path[0] = DAI_ADDRESS;
    //     path[1] = _WETH_ADDRESS;

    //     vm.deal(address(positionFolding), 0.01 ether);
    //     vm.expectRevert(ILendtroller.InsufficientLiquidity.selector);
    //     positionFolding.leverageMax(
    //         CToken(address(cDAI)),
    //         CToken(address(cETH)),
    //         PositionFolding.Swap({ target: address(0), call: "0x" }),
    //         3000
    //     );

    //     vm.stopPrank();
    // }
}
