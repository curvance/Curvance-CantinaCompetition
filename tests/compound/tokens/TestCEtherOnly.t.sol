// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "contracts/compound/Comptroller/Comptroller.sol";
import "contracts/compound/Comptroller/ComptrollerInterface.sol";
import "contracts/compound/Token/CEther.sol";
import "contracts/compound/Oracle/SimplePriceOracle.sol";
import "contracts/compound/InterestRateModel/InterestRateModel.sol";
import { GaugePool } from "contracts/gauge/GaugePool.sol";

import "tests/compound/deploy.sol";
import "tests/utils/TestBase.sol";
import "forge-std/console.sol";

contract User {}

contract TestCEther is TestBase {
    address public admin;
    address public user;
    address public liquidator;
    DeployCompound public deployments;
    address public unitroller;
    CEther public cETH;
    SimplePriceOracle public priceOracle;
    address gauge;

    receive() external payable {}

    fallback() external payable {}

    function setUp() public {
        deployments = new DeployCompound();
        deployments.makeCompound();
        unitroller = address(deployments.unitroller());
        priceOracle = SimplePriceOracle(deployments.priceOracle());
        priceOracle.setDirectPrice(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, _ONE);

        admin = deployments.admin();
        user = address(this);
        liquidator = address(new User());

        // prepare 200K ETH
        vm.deal(user, 200000e18);
        vm.deal(liquidator, 200000e18);

        gauge = address(new GaugePool(address(0), address(0), unitroller));
    }

    function testInitialize() public {
        cETH = new CEther(
            ComptrollerInterface(unitroller),
            gauge,
            InterestRateModel(address(deployments.jumpRateModel())),
            _ONE,
            "cETH",
            "cETH",
            18,
            payable(admin)
        );
    }

    function testMint() public {
        cETH = new CEther(
            ComptrollerInterface(unitroller),
            gauge,
            InterestRateModel(address(deployments.jumpRateModel())),
            _ONE,
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
        Comptroller(unitroller)._setCollateralFactor(CToken(address(cETH)), 5e17);

        // enter markets
        vm.prank(user);
        address[] memory markets = new address[](1);
        markets[0] = address(cETH);
        ComptrollerInterface(unitroller).enterMarkets(markets);

        // mint
        cETH.mint{ value: 100e18 }();
        assertGt(cETH.balanceOf(user), 0);
    }

    function testRedeem() public {
        cETH = new CEther(
            ComptrollerInterface(unitroller),
            gauge,
            InterestRateModel(address(deployments.jumpRateModel())),
            _ONE,
            "cETH",
            "cETH",
            18,
            payable(admin)
        );
        // support market
        vm.prank(admin);
        Comptroller(unitroller)._supportMarket(CToken(address(cETH)));
        vm.prank(admin);
        Comptroller(unitroller)._setCollateralFactor(CToken(address(cETH)), 5e17);

        // enter markets
        vm.prank(user);
        address[] memory markets = new address[](1);
        markets[0] = address(cETH);
        ComptrollerInterface(unitroller).enterMarkets(markets);

        uint256 balanceBeforeMint = user.balance;
        // mint
        cETH.mint{ value: 100e18 }();
        assertEq(cETH.balanceOf(user), 100e18);
        assertGt(balanceBeforeMint, user.balance);

        // redeem
        cETH.redeem(cETH.balanceOf(user));
        assertEq(cETH.balanceOf(user), 0);
        assertEq(balanceBeforeMint, user.balance);
    }

    function testRedeemUnderlying() public {
        cETH = new CEther(
            ComptrollerInterface(unitroller),
            gauge,
            InterestRateModel(address(deployments.jumpRateModel())),
            _ONE,
            "cETH",
            "cETH",
            18,
            payable(admin)
        );
        // support market
        vm.prank(admin);
        Comptroller(unitroller)._supportMarket(CToken(address(cETH)));
        vm.prank(admin);
        Comptroller(unitroller)._setCollateralFactor(CToken(address(cETH)), 5e17);

        // enter markets
        vm.prank(user);
        address[] memory markets = new address[](1);
        markets[0] = address(cETH);
        ComptrollerInterface(unitroller).enterMarkets(markets);

        uint256 balanceBeforeMint = user.balance;
        // mint
        cETH.mint{ value: 100e18 }();
        assertEq(cETH.balanceOf(user), 100e18);
        assertGt(balanceBeforeMint, user.balance);

        // redeem
        cETH.redeemUnderlying(100e18);
        assertEq(cETH.balanceOf(user), 0);
        assertEq(balanceBeforeMint, user.balance);
    }

    function testBorrow() public {
        cETH = new CEther(
            ComptrollerInterface(unitroller),
            gauge,
            InterestRateModel(address(deployments.jumpRateModel())),
            _ONE,
            "cETH",
            "cETH",
            18,
            payable(admin)
        );
        // support market
        vm.prank(admin);
        Comptroller(unitroller)._supportMarket(CToken(address(cETH)));
        vm.prank(admin);
        Comptroller(unitroller)._setCollateralFactor(CToken(address(cETH)), 5e17);

        // enter markets
        vm.prank(user);
        address[] memory markets = new address[](1);
        markets[0] = address(cETH);
        ComptrollerInterface(unitroller).enterMarkets(markets);

        // mint
        cETH.mint{ value: 100e18 }();
        assertEq(cETH.balanceOf(user), 100e18);

        uint256 balanceBeforeBorrow = user.balance;
        // borrow
        cETH.borrow(50e18);
        assertEq(cETH.balanceOf(user), 100e18);
        assertEq(balanceBeforeBorrow + 50e18, user.balance);
    }

    function testRepayBorrow() public {
        cETH = new CEther(
            ComptrollerInterface(unitroller),
            gauge,
            InterestRateModel(address(deployments.jumpRateModel())),
            _ONE,
            "cETH",
            "cETH",
            18,
            payable(admin)
        );
        // support market
        vm.prank(admin);
        Comptroller(unitroller)._supportMarket(CToken(address(cETH)));
        vm.prank(admin);
        Comptroller(unitroller)._setCollateralFactor(CToken(address(cETH)), 5e17);

        // enter markets
        vm.prank(user);
        address[] memory markets = new address[](1);
        markets[0] = address(cETH);
        ComptrollerInterface(unitroller).enterMarkets(markets);

        // mint
        cETH.mint{ value: 100e18 }();
        assertEq(cETH.balanceOf(user), 100e18);

        uint256 balanceBeforeBorrow = user.balance;
        // borrow
        cETH.borrow(50e18);
        assertEq(cETH.balanceOf(user), 100e18);
        assertEq(balanceBeforeBorrow + 50e18, user.balance);

        // repay
        cETH.repayBorrow{ value: 50e18 }();
        assertEq(balanceBeforeBorrow, user.balance);
    }

    function testRepayBorrowBehalf() public {
        cETH = new CEther(
            ComptrollerInterface(unitroller),
            gauge,
            InterestRateModel(address(deployments.jumpRateModel())),
            _ONE,
            "cETH",
            "cETH",
            18,
            payable(admin)
        );
        // support market
        vm.prank(admin);
        Comptroller(unitroller)._supportMarket(CToken(address(cETH)));
        vm.prank(admin);
        Comptroller(unitroller)._setCollateralFactor(CToken(address(cETH)), 5e17);

        // enter markets
        vm.prank(user);
        address[] memory markets = new address[](1);
        markets[0] = address(cETH);
        ComptrollerInterface(unitroller).enterMarkets(markets);

        // mint
        cETH.mint{ value: 100e18 }();
        assertEq(cETH.balanceOf(user), 100e18);

        uint256 balanceBeforeBorrow = user.balance;
        // borrow
        cETH.borrow(50e18);
        assertEq(cETH.balanceOf(user), 100e18);
        assertEq(balanceBeforeBorrow + 50e18, user.balance);

        // repay
        cETH.repayBorrowBehalf{ value: 50e18 }(user);
        assertEq(balanceBeforeBorrow, user.balance);
    }

    function testLiquidateBorrow() public {
        cETH = new CEther(
            ComptrollerInterface(unitroller),
            gauge,
            InterestRateModel(address(deployments.jumpRateModel())),
            _ONE,
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
        Comptroller(unitroller)._setCollateralFactor(CToken(address(cETH)), 6e17);

        // enter markets
        vm.prank(user);
        address[] memory markets = new address[](1);
        markets[0] = address(cETH);
        ComptrollerInterface(unitroller).enterMarkets(markets);

        // mint
        cETH.mint{ value: 100e18 }();
        assertEq(cETH.balanceOf(user), 100e18);

        // borrow
        cETH.borrow(60e18);
        assertEq(cETH.balanceOf(user), 100e18);

        // set collateral factor
        vm.prank(admin);
        Comptroller(unitroller)._setCollateralFactor(CToken(address(cETH)), 5e17);

        // liquidateBorrow
        vm.prank(liquidator);
        cETH.liquidateBorrow{ value: 12e18 }(user, CToken(cETH));

        assertEq(cETH.balanceOf(liquidator), 5832000000000000000);
    }
}
