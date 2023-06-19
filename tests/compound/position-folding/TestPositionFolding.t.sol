// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "contracts/compound/Comptroller/Comptroller.sol";
import "contracts/compound/Comptroller/ComptrollerInterface.sol";
import "contracts/compound/Token/CErc20Immutable.sol";
import "contracts/compound/Token/CEther.sol";
import "contracts/compound/Oracle/SimplePriceOracle.sol";
import "contracts/compound/InterestRateModel/InterestRateModel.sol";
import { PositionFolding } from "contracts/PositionFolding/PositionFolding.sol";
import { GaugePool } from "contracts/gauge/GaugePool.sol";

import "tests/compound/deploy.sol";
import "tests/utils/TestBase.sol";
import "forge-std/console.sol";

contract User {
    receive() external payable {}

    fallback() external payable {}
}

contract TestPositionFolding is TestBase {
    address public uniswapV2Router = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address public weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address public dai = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    address public admin;
    address public user;
    DeployCompound public deployments;
    address public unitroller;
    CErc20Immutable public cDAI;
    CEther public cETH;
    SimplePriceOracle public priceOracle;
    address public gauge;
    PositionFolding public positionFolding;

    receive() external payable {}

    fallback() external payable {}

    function setUp() public {
        deployments = new DeployCompound();
        deployments.makeCompound();
        unitroller = address(deployments.unitroller());
        priceOracle = SimplePriceOracle(deployments.priceOracle());
        priceOracle.setDirectPrice(dai, 1 ether);
        priceOracle.setDirectPrice(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, 2000 ether);

        admin = deployments.admin();
        user = address(this);

        // prepare 200K DAI
        vm.store(
            dai,
            keccak256(abi.encodePacked(uint256(uint160(user)), uint256(2))),
            bytes32(uint256(200000 ether))
        );
        // prepare 200K ETH
        vm.deal(user, 200000 ether);

        gauge = address(new GaugePool(address(0), address(0), unitroller));

        cDAI = new CErc20Immutable(
            dai,
            ComptrollerInterface(unitroller),
            gauge,
            InterestRateModel(address(deployments.jumpRateModel())),
            1 ether,
            "cDAI",
            "cDAI",
            18,
            payable(admin)
        );
        // support market
        vm.prank(admin);
        Comptroller(unitroller)._supportMarket(CToken(address(cDAI)));
        // set collateral factor
        vm.prank(admin);
        Comptroller(unitroller)._setCollateralFactor(CToken(address(cDAI)), 75e16);

        cETH = new CEther(
            ComptrollerInterface(unitroller),
            gauge,
            InterestRateModel(address(deployments.jumpRateModel())),
            1 ether,
            "cETH",
            "cETH",
            18,
            payable(admin)
        );
        // support market
        vm.prank(admin);
        Comptroller(unitroller)._supportMarket(CToken(address(cETH)));
        // set collateral factor
        vm.prank(admin);
        Comptroller(unitroller)._setCollateralFactor(CToken(address(cETH)), 75e16);

        positionFolding = new PositionFolding(unitroller, address(priceOracle), address(cETH), weth);
        // set position folding
        vm.prank(admin);
        Comptroller(unitroller)._setPositionFolding(address(positionFolding));

        // provide enough liquidity for leverage
        provideEnoughLiquidityForLeverage();
    }

    function provideEnoughLiquidityForLeverage() internal {
        address liquidityProvider = address(new User());
        vm.startPrank(liquidityProvider);
        // prepare 200K DAI
        vm.store(
            dai,
            keccak256(abi.encodePacked(uint256(uint160(liquidityProvider)), uint256(2))),
            bytes32(uint256(200000 ether))
        );
        // prepare 200K ETH
        vm.deal(liquidityProvider, 200000 ether);
        address[] memory markets = new address[](2);
        markets[0] = address(cDAI);
        markets[1] = address(cETH);
        ComptrollerInterface(unitroller).enterMarkets(markets);

        // mint cDAI
        IERC20(dai).approve(address(cDAI), 200000 ether);
        cDAI.mint(200000 ether);

        // mint cETH
        cETH.mint{ value: 200000 ether }();

        vm.stopPrank();
    }

    function testLeverageMaxWithOnlyCToken() public {
        // enter markets
        vm.startPrank(user);
        address[] memory markets = new address[](1);
        markets[0] = address(cDAI);
        ComptrollerInterface(unitroller).enterMarkets(markets);

        // approve
        IERC20(dai).approve(address(cDAI), 100 ether);

        // mint
        assertTrue(cDAI.mint(100 ether));
        assertEq(cDAI.balanceOf(user), 100 ether);

        uint256 balanceBeforeBorrow = IERC20(dai).balanceOf(user);
        // borrow
        cDAI.borrow(25 ether);
        assertEq(cDAI.balanceOf(user), 100 ether);
        assertEq(balanceBeforeBorrow + 25 ether, IERC20(dai).balanceOf(user));

        assertEq(positionFolding.queryAmountToBorrowForLeverageMax(user, CToken(address(cDAI))), 145 ether);
        positionFolding.leverageMax(
            CToken(address(cDAI)),
            CToken(address(cDAI)),
            PositionFolding.Swap({ target: address(0), call: "0x" }),
            3000
        );

        (uint256 cTokenBalance, uint256 borrowBalance, ) = cDAI.getAccountSnapshot(user);
        assertEq(cTokenBalance, 245 ether);
        assertEq(borrowBalance, 170 ether);

        vm.stopPrank();
    }

    function testDeLeverageWithOnlyCToken() public {
        // enter markets
        vm.startPrank(user);
        address[] memory markets = new address[](1);
        markets[0] = address(cDAI);
        ComptrollerInterface(unitroller).enterMarkets(markets);

        // approve
        IERC20(dai).approve(address(cDAI), 100 ether);

        // mint
        assertTrue(cDAI.mint(100 ether));
        assertEq(cDAI.balanceOf(user), 100 ether);

        uint256 balanceBeforeBorrow = IERC20(dai).balanceOf(user);
        // borrow
        cDAI.borrow(25 ether);
        assertEq(cDAI.balanceOf(user), 100 ether);
        assertEq(balanceBeforeBorrow + 25 ether, IERC20(dai).balanceOf(user));

        assertEq(positionFolding.queryAmountToBorrowForLeverageMax(user, CToken(address(cDAI))), 145 ether);
        positionFolding.leverageMax(
            CToken(address(cDAI)),
            CToken(address(cDAI)),
            PositionFolding.Swap({ target: address(0), call: "0x" }),
            3000
        );

        (uint256 cTokenBalance, uint256 borrowBalance, ) = cDAI.getAccountSnapshot(user);
        assertEq(cTokenBalance, 245 ether);
        assertEq(borrowBalance, 170 ether);

        positionFolding.deleverage(
            CToken(address(cDAI)),
            170 ether,
            CToken(address(cDAI)),
            170 ether,
            PositionFolding.Swap({ target: address(0), call: "0x" }),
            3000
        );

        (cTokenBalance, borrowBalance, ) = cDAI.getAccountSnapshot(user);
        assertEq(cTokenBalance, 75 ether);
        assertEq(borrowBalance, 0 ether);

        vm.stopPrank();
    }

    function testLeverageMaxWithOnlyCEther() public {
        // enter markets
        vm.startPrank(user);
        address[] memory markets = new address[](1);
        markets[0] = address(cETH);
        ComptrollerInterface(unitroller).enterMarkets(markets);

        // mint
        cETH.mint{ value: 100 ether }();
        assertEq(cETH.balanceOf(user), 100 ether);

        uint256 balanceBeforeBorrow = user.balance;
        // borrow
        cETH.borrow(25 ether);
        assertEq(cETH.balanceOf(user), 100 ether);
        assertEq(balanceBeforeBorrow + 25 ether, user.balance);

        assertEq(positionFolding.queryAmountToBorrowForLeverageMax(user, CToken(address(cETH))), 145 ether);
        positionFolding.leverageMax(
            CToken(address(cETH)),
            CToken(address(cETH)),
            PositionFolding.Swap({ target: address(0), call: "0x" }),
            3000
        );

        (uint256 cTokenBalance, uint256 borrowBalance, ) = cETH.getAccountSnapshot(user);
        assertEq(cTokenBalance, 245 ether);
        assertEq(borrowBalance, 170 ether);

        vm.stopPrank();
    }

    function testDeLeverageWithOnlyCEther() public {
        // enter markets
        vm.startPrank(user);
        address[] memory markets = new address[](1);
        markets[0] = address(cETH);
        ComptrollerInterface(unitroller).enterMarkets(markets);

        // mint
        cETH.mint{ value: 100 ether }();
        assertEq(cETH.balanceOf(user), 100 ether);

        uint256 balanceBeforeBorrow = user.balance;
        // borrow
        cETH.borrow(25 ether);
        assertEq(cETH.balanceOf(user), 100 ether);
        assertEq(balanceBeforeBorrow + 25 ether, user.balance);

        assertEq(positionFolding.queryAmountToBorrowForLeverageMax(user, CToken(address(cETH))), 145 ether);
        positionFolding.leverageMax(
            CToken(address(cETH)),
            CToken(address(cETH)),
            PositionFolding.Swap({ target: address(0), call: "0x" }),
            3000
        );

        (uint256 cTokenBalance, uint256 borrowBalance, ) = cETH.getAccountSnapshot(user);
        assertEq(cTokenBalance, 245 ether);
        assertEq(borrowBalance, 170 ether);

        positionFolding.deleverage(
            CToken(address(cETH)),
            170 ether,
            CToken(address(cETH)),
            170 ether,
            PositionFolding.Swap({ target: address(0), call: "0x" }),
            3000
        );

        (cTokenBalance, borrowBalance, ) = cETH.getAccountSnapshot(user);
        assertEq(cTokenBalance, 75 ether);
        assertEq(borrowBalance, 0 ether);

        vm.stopPrank();
    }

    function testLeverageMaxIntegration1() public {
        // enter markets
        vm.startPrank(user);
        address[] memory markets = new address[](2);
        markets[0] = address(cDAI);
        markets[1] = address(cETH);
        ComptrollerInterface(unitroller).enterMarkets(markets);

        // mint 2000 dai
        IERC20(dai).approve(address(cDAI), 2000 ether);
        cDAI.mint(2000 ether);

        // mint 1 ether
        cETH.mint{ value: 1 ether }();

        // borrow 500 dai
        cDAI.borrow(500 ether);

        // borrow 0.25 ether
        cETH.borrow(0.25 ether);

        uint256 amountForLeverage = positionFolding.queryAmountToBorrowForLeverageMax(user, CToken(address(cDAI)));
        assertEq(amountForLeverage, 5800 ether);

        address[] memory path = new address[](2);
        path[0] = dai;
        path[1] = weth;
        positionFolding.leverageMax(
            CToken(address(cDAI)),
            CToken(address(cETH)),
            PositionFolding.Swap({
                target: uniswapV2Router,
                call: abi.encodeWithSignature(
                    "swapExactTokensForETH(uint256,uint256,address[],address,uint256)",
                    amountForLeverage,
                    0,
                    path,
                    address(positionFolding),
                    block.timestamp
                )
            }),
            3000
        );

        (uint256 cDAIBalance, uint256 daiBorrowBalance, ) = cDAI.getAccountSnapshot(user);
        (uint256 cETHBalance, uint256 ethBorrowBalance, ) = cETH.getAccountSnapshot(user);
        assertEq(cDAIBalance, 2000 ether); // $2000
        assertGt(cETHBalance, 3.7 ether); // $7400
        assertEq(daiBorrowBalance, 6300 ether); // $6300
        assertEq(ethBorrowBalance, 0.25 ether); // $500

        (uint256 sumCollateral, uint256 maxBorrow, uint256 sumBorrow) = Comptroller(unitroller).getAccountPosition(
            user
        );
        assertGt(sumCollateral, 9400 ether);
        assertGt(maxBorrow, (9400 ether * 75) / 100);
        assertEq(sumBorrow, 6800 ether);

        vm.stopPrank();
    }

    function testDeLeverageIntegration1() public {
        vm.startPrank(user);

        {
            // enter markets
            address[] memory markets = new address[](2);
            markets[0] = address(cDAI);
            markets[1] = address(cETH);
            ComptrollerInterface(unitroller).enterMarkets(markets);
        }

        // mint 2000 dai
        IERC20(dai).approve(address(cDAI), 2000 ether);
        cDAI.mint(2000 ether);

        // mint 1 ether
        cETH.mint{ value: 1 ether }();

        // borrow 500 dai
        cDAI.borrow(500 ether);

        // borrow 0.25 ether
        cETH.borrow(0.25 ether);

        {
            uint256 amountForLeverage = positionFolding.queryAmountToBorrowForLeverageMax(user, CToken(address(cDAI)));
            assertEq(amountForLeverage, 5800 ether);

            address[] memory path = new address[](2);
            path[0] = dai;
            path[1] = weth;

            positionFolding.leverageMax(
                CToken(address(cDAI)),
                CToken(address(cETH)),
                PositionFolding.Swap({
                    target: uniswapV2Router,
                    call: abi.encodeWithSignature(
                        "swapExactTokensForETH(uint256,uint256,address[],address,uint256)",
                        amountForLeverage,
                        0,
                        path,
                        address(positionFolding),
                        block.timestamp
                    )
                }),
                3000
            );
        }

        {
            (uint256 cDAIBalance, uint256 daiBorrowBalance, ) = cDAI.getAccountSnapshot(user);
            (uint256 cETHBalance, uint256 ethBorrowBalance, ) = cETH.getAccountSnapshot(user);
            assertEq(cDAIBalance, 2000 ether); // $2000
            assertGt(cETHBalance, 3.7 ether); // $7400
            assertEq(daiBorrowBalance, 6300 ether); // $6300
            assertEq(ethBorrowBalance, 0.25 ether); // $500

            (uint256 sumCollateral, uint256 maxBorrow, uint256 sumBorrow) = Comptroller(unitroller).getAccountPosition(
                user
            );
            assertGt(sumCollateral, 9400 ether);
            assertGt(maxBorrow, (9400 ether * 75) / 100);
            assertEq(sumBorrow, 6800 ether);
        }

        {
            address[] memory path = new address[](2);
            path[0] = weth;
            path[1] = dai;
            positionFolding.deleverage(
                CToken(address(cETH)),
                3.7 ether,
                CToken(address(cDAI)),
                6300 ether,
                PositionFolding.Swap({
                    target: uniswapV2Router,
                    call: abi.encodeWithSignature(
                        "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)",
                        3.7 ether,
                        0,
                        path,
                        address(positionFolding),
                        block.timestamp
                    )
                }),
                3000
            );
        }

        {
            (uint256 cDAIBalance, uint256 daiBorrowBalance, ) = cDAI.getAccountSnapshot(user);
            (uint256 cETHBalance, uint256 ethBorrowBalance, ) = cETH.getAccountSnapshot(user);
            assertGt(cDAIBalance, 2000 ether); // $2000
            assertGt(cETHBalance, 0 ether); // $7400
            assertEq(daiBorrowBalance, 0 ether); // $6300
            assertEq(ethBorrowBalance, 0.25 ether); // $500

            (uint256 sumCollateral, uint256 maxBorrow, uint256 sumBorrow) = Comptroller(unitroller).getAccountPosition(
                user
            );
            assertGt(sumCollateral, 2000 ether);
            assertGt(maxBorrow, (2000 ether * 75) / 100);
            assertEq(sumBorrow, 500 ether);
        }

        vm.stopPrank();
    }

    function testLeverageMaxCheckAccountHealthy() public {
        // enter markets
        vm.startPrank(user);
        address[] memory markets = new address[](2);
        markets[0] = address(cDAI);
        markets[1] = address(cETH);
        ComptrollerInterface(unitroller).enterMarkets(markets);

        // mint 2000 dai
        IERC20(dai).approve(address(cDAI), 2000 ether);
        cDAI.mint(2000 ether);

        // mint 1 ether
        cETH.mint{ value: 1 ether }();

        // borrow 500 dai
        cDAI.borrow(500 ether);

        // borrow 0.25 ether
        cETH.borrow(0.25 ether);

        uint256 amountForLeverage = positionFolding.queryAmountToBorrowForLeverageMax(user, CToken(address(cDAI)));
        assertEq(amountForLeverage, 5800 ether);

        address[] memory path = new address[](2);
        path[0] = dai;
        path[1] = weth;

        vm.deal(address(positionFolding), 0.01 ether);
        vm.expectRevert(bytes4(keccak256("InsufficientLiquidity()")));
        positionFolding.leverageMax(
            CToken(address(cDAI)),
            CToken(address(cETH)),
            PositionFolding.Swap({ target: address(0), call: "0x" }),
            3000
        );

        vm.stopPrank();
    }
}
