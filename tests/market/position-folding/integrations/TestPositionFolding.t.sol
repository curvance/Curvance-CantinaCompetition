// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { IMToken } from "contracts/interfaces/market/IMToken.sol";
import { IUniswapV2Router } from "contracts/interfaces/external/uniswap/IUniswapV2Router.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";

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

        // vm.warp(gaugePool.startTime());
        // vm.roll(block.number + 1000);

        // // set gauge settings of next epoch
        // address[] memory tokensParam = new address[](2);
        // tokensParam[0] = address(dDAI);
        // tokensParam[1] = address(cBALRETH);
        // uint256[] memory poolWeights = new uint256[](2);
        // poolWeights[0] = 100;
        // poolWeights[1] = 100;
        // vm.prank(protocolMessagingHub);
        // gaugePool.setEmissionRates(1, tokensParam, poolWeights);
        // vm.prank(protocolMessagingHub);
        // cve.mintGaugeEmissions(300 * 2 weeks, address(gaugePool));
        // vm.warp(gaugePool.startTime() + 1 * 2 weeks);

        // provide enough liquidity for leverage
        provideEnoughLiquidityForLeverage();

        centralRegistry.addSwapper(_UNISWAP_V2_ROUTER);
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

    function testLeverage() public {
        vm.startPrank(user);

        // approve
        balRETH.approve(address(cBALRETH), 1 ether);

        // mint
        assertTrue(cBALRETH.mint(1 ether));
        assertEq(cBALRETH.balanceOf(user), 1 ether);

        uint256 balanceBeforeBorrow = dai.balanceOf(user);
        // borrow
        dDAI.borrow(100 ether);
        assertEq(balanceBeforeBorrow + 100 ether, dai.balanceOf(user));

        // try leverage with 80% of max
        uint256 amountForLeverage = (positionFolding
            .queryAmountToBorrowForLeverageMax(user, address(dDAI)) * 80) /
            100;

        PositionFolding.LeverageStruct memory leverageData;
        leverageData.borrowToken = dDAI;
        leverageData.borrowAmount = amountForLeverage;
        leverageData.collateralToken = cBALRETH;
        leverageData.swapData.inputToken = address(dai);
        leverageData.swapData.inputAmount = amountForLeverage;
        leverageData.swapData.outputToken = _WETH_ADDRESS;
        leverageData.swapData.target = _UNISWAP_V2_ROUTER;
        address[] memory path = new address[](2);
        path[0] = address(dai);
        path[1] = _WETH_ADDRESS;
        leverageData.swapData.call = abi.encodeWithSignature(
            "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)",
            amountForLeverage,
            0,
            path,
            address(positionFolding),
            block.timestamp
        );
        leverageData.zapperCall.inputToken = _WETH_ADDRESS;
        uint256[] memory amountsOut = IUniswapV2Router(_UNISWAP_V2_ROUTER)
            .getAmountsOut(amountForLeverage, path);
        leverageData.zapperCall.inputAmount = amountsOut[1];

        address[] memory tokens = new address[](2);
        tokens[0] = _RETH_ADDRESS;
        tokens[1] = _WETH_ADDRESS;
        leverageData.zapperCall.target = address(zapper);
        leverageData.zapperCall.call = abi.encodeWithSelector(
            Zapper.balancerIn.selector,
            address(cBALRETH),
            Zapper.ZapperData(
                _WETH_ADDRESS,
                leverageData.zapperCall.inputAmount,
                address(balRETH),
                0
            ),
            new SwapperLib.Swap[](0),
            _BALANCER_VAULT,
            _BAL_WETH_RETH_POOLID,
            tokens,
            user
        );

        positionFolding.leverage(leverageData, 500);

        (uint256 dDAIBalance, uint256 dDAIBorrowed, ) = dDAI
            .getAccountSnapshot(user);
        assertEq(dDAIBalance, 0);
        assertEq(dDAIBorrowed, 100 ether + amountForLeverage);

        (uint256 cBALRETHBalance, uint256 cBALRETHBorrowed, ) = cBALRETH
            .getAccountSnapshot(user);
        assertGt(cBALRETHBalance, 1.5 ether);
        assertEq(cBALRETHBorrowed, 0 ether);

        vm.stopPrank();
    }

    function testDeLeverage() public {
        testLeverage();
        vm.warp(block.timestamp + 15 minutes);
        dDAI.accrueInterest();

        vm.startPrank(user);

        PositionFolding.DeleverageStruct memory deleverageData;

        (, uint256 dDAIBorrowedBefore, ) = dDAI.getAccountSnapshot(user);
        (uint256 cBALRETHBalanceBefore, , ) = cBALRETH.getAccountSnapshot(
            user
        );

        deleverageData.collateralToken = cBALRETH;
        deleverageData.collateralAmount = 0.3 ether;
        deleverageData.borrowToken = dDAI;

        deleverageData.zapperCall.inputToken = address(balRETH);
        deleverageData.zapperCall.inputAmount = deleverageData
            .collateralAmount;

        address[] memory tokens = new address[](2);
        tokens[0] = _RETH_ADDRESS;
        tokens[1] = _WETH_ADDRESS;
        deleverageData.zapperCall.target = address(zapper);
        deleverageData.zapperCall.call = abi.encodeWithSelector(
            Zapper.balancerOut.selector,
            _BALANCER_VAULT,
            _BAL_WETH_RETH_POOLID,
            Zapper.ZapperData(
                address(balRETH),
                deleverageData.zapperCall.inputAmount,
                _WETH_ADDRESS,
                0
            ),
            tokens,
            true,
            1,
            new SwapperLib.Swap[](0),
            address(positionFolding)
        );

        uint256 amountForDeleverage = 0.3 ether;
        deleverageData.swapData.inputToken = _WETH_ADDRESS;
        deleverageData.swapData.inputAmount = amountForDeleverage;
        deleverageData.swapData.outputToken = address(dai);
        deleverageData.swapData.target = _UNISWAP_V2_ROUTER;
        address[] memory path = new address[](2);
        path[0] = _WETH_ADDRESS;
        path[1] = address(dai);
        deleverageData.swapData.call = abi.encodeWithSignature(
            "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)",
            amountForDeleverage,
            0,
            path,
            address(positionFolding),
            block.timestamp
        );
        uint256[] memory amountsOut = IUniswapV2Router(_UNISWAP_V2_ROUTER)
            .getAmountsOut(amountForDeleverage, path);
        deleverageData.repayAmount = amountsOut[1];

        positionFolding.deleverage(deleverageData, 500);

        (uint256 dDAIBalance, uint256 dDAIBorrowed, ) = dDAI
            .getAccountSnapshot(user);
        assertEq(dDAIBalance, 0);
        assertEq(
            dDAIBorrowed,
            dDAIBorrowedBefore - deleverageData.repayAmount
        );

        (uint256 cBALRETHBalance, uint256 cBALRETHBorrowed, ) = cBALRETH
            .getAccountSnapshot(user);
        assertEq(
            cBALRETHBalance,
            cBALRETHBalanceBefore - deleverageData.collateralAmount
        );
        assertEq(cBALRETHBorrowed, 0);

        vm.stopPrank();
    }
}
