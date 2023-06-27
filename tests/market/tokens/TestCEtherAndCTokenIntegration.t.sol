// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "contracts/market/lendtroller/Lendtroller.sol";
import "contracts/market/lendtroller/LendtrollerInterface.sol";
import "contracts/market/Token/CErc20Immutable.sol";
import "contracts/market/Token/CEther.sol";
import "contracts/market/Oracle/SimplePriceOracle.sol";
import "contracts/market/InterestRateModel/InterestRateModel.sol";
import { GaugePool } from "contracts/gauge/GaugePool.sol";

import "tests/compound/deploy.sol";
import "tests/utils/TestBase.sol";

contract User {}

contract TestCEtherAndCTokenIntegration is TestBase {
    address public dai = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    address public admin;
    address public user;
    address public liquidator;
    DeployCompound public deployments;
    address public unitroller;
    CErc20Immutable public cDAI;
    CEther public cETH;
    SimplePriceOracle public priceOracle;
    address gauge;

    receive() external payable {}

    fallback() external payable {}

    function setUp() public {
        _fork();

        deployments = new DeployCompound();
        deployments.makeCompound();
        unitroller = address(deployments.unitroller());
        priceOracle = SimplePriceOracle(deployments.priceOracle());
        priceOracle.setDirectPrice(dai, _ONE);
        priceOracle.setDirectPrice(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, 1000e18);

        admin = deployments.admin();
        user = address(this);
        liquidator = address(new User());

        // prepare 200K DAI
        vm.store(dai, keccak256(abi.encodePacked(uint256(uint160(user)), uint256(2))), bytes32(uint256(200000e18)));
        vm.store(
            dai,
            keccak256(abi.encodePacked(uint256(uint160(liquidator)), uint256(2))),
            bytes32(uint256(200000e18))
        );
        // prepare 100 ETH
        vm.deal(user, 100e18);
        vm.deal(liquidator, 100e18);

        gauge = address(new GaugePool(address(0), address(0), unitroller));
    }

    function testInitialize() public {
        cDAI = new CErc20Immutable(
            dai,
            LendtrollerInterface(unitroller),
            gauge,
            InterestRateModel(address(deployments.jumpRateModel())),
            _ONE,
            "cDAI",
            "cDAI",
            18,
            payable(admin)
        );
        cETH = new CEther(
            LendtrollerInterface(unitroller),
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
        cDAI = new CErc20Immutable(
            dai,
            LendtrollerInterface(unitroller),
            gauge,
            InterestRateModel(address(deployments.jumpRateModel())),
            _ONE,
            "cDAI",
            "cDAI",
            18,
            payable(admin)
        );
        cETH = new CEther(
            LendtrollerInterface(unitroller),
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
        Lendtroller(unitroller)._supportMarket(CToken(address(cDAI)));
        vm.prank(admin);
        Lendtroller(unitroller)._supportMarket(CToken(address(cETH)));
        // set collateral factor
        vm.prank(admin);
        Lendtroller(unitroller)._setCollateralFactor(CToken(address(cDAI)), 5e17);
        vm.prank(admin);
        Lendtroller(unitroller)._setCollateralFactor(CToken(address(cETH)), 5e17);

        // enter markets
        vm.prank(user);
        address[] memory markets = new address[](2);
        markets[0] = address(cDAI);
        markets[1] = address(cETH);
        LendtrollerInterface(unitroller).enterMarkets(markets);

        // mint cDAI
        IERC20(dai).approve(address(cDAI), 100e18);
        assertTrue(cDAI.mint(100e18));
        assertGt(cDAI.balanceOf(user), 0);

        // mint cETH
        cETH.mint{ value: 10e18 }();
        assertGt(cETH.balanceOf(user), 0);
    }

    function testRedeem() public {
        cDAI = new CErc20Immutable(
            dai,
            LendtrollerInterface(unitroller),
            gauge,
            InterestRateModel(address(deployments.jumpRateModel())),
            _ONE,
            "cDAI",
            "cDAI",
            18,
            payable(admin)
        );
        cETH = new CEther(
            LendtrollerInterface(unitroller),
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
        Lendtroller(unitroller)._supportMarket(CToken(address(cDAI)));
        vm.prank(admin);
        Lendtroller(unitroller)._supportMarket(CToken(address(cETH)));
        // set collateral factor
        vm.prank(admin);
        Lendtroller(unitroller)._setCollateralFactor(CToken(address(cDAI)), 5e17);
        vm.prank(admin);
        Lendtroller(unitroller)._setCollateralFactor(CToken(address(cETH)), 5e17);

        // enter markets
        vm.prank(user);
        address[] memory markets = new address[](2);
        markets[0] = address(cDAI);
        markets[1] = address(cETH);
        LendtrollerInterface(unitroller).enterMarkets(markets);

        uint256 daiBalanceBeforeMint = IERC20(dai).balanceOf(user);
        uint256 ethBalanceBeforeMint = user.balance;

        // mint cDAI
        IERC20(dai).approve(address(cDAI), 100e18);
        assertTrue(cDAI.mint(100e18));

        // mint cETH
        cETH.mint{ value: 10e18 }();

        // redeem DAI
        cDAI.redeem(cDAI.balanceOf(user));
        assertEq(cDAI.balanceOf(user), 0);
        assertEq(daiBalanceBeforeMint, IERC20(dai).balanceOf(user));

        // redeem ETH
        cETH.redeem(cETH.balanceOf(user));
        assertEq(cETH.balanceOf(user), 0);
        assertEq(ethBalanceBeforeMint, user.balance);
    }

    function testRedeemUnderlying() public {
        cDAI = new CErc20Immutable(
            dai,
            LendtrollerInterface(unitroller),
            gauge,
            InterestRateModel(address(deployments.jumpRateModel())),
            _ONE,
            "cDAI",
            "cDAI",
            18,
            payable(admin)
        );
        cETH = new CEther(
            LendtrollerInterface(unitroller),
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
        Lendtroller(unitroller)._supportMarket(CToken(address(cDAI)));
        vm.prank(admin);
        Lendtroller(unitroller)._supportMarket(CToken(address(cETH)));
        // set collateral factor
        vm.prank(admin);
        Lendtroller(unitroller)._setCollateralFactor(CToken(address(cDAI)), 5e17);
        vm.prank(admin);
        Lendtroller(unitroller)._setCollateralFactor(CToken(address(cETH)), 5e17);

        // enter markets
        vm.prank(user);
        address[] memory markets = new address[](2);
        markets[0] = address(cDAI);
        markets[1] = address(cETH);
        LendtrollerInterface(unitroller).enterMarkets(markets);

        uint256 daiBalanceBeforeMint = IERC20(dai).balanceOf(user);
        uint256 ethBalanceBeforeMint = user.balance;

        // mint cDAI
        IERC20(dai).approve(address(cDAI), 100e18);
        assertTrue(cDAI.mint(100e18));

        // mint cETH
        cETH.mint{ value: 10e18 }();

        // redeem
        cDAI.redeemUnderlying(100e18);
        assertEq(cDAI.balanceOf(user), 0);
        assertEq(daiBalanceBeforeMint, IERC20(dai).balanceOf(user));

        // redeem
        cETH.redeemUnderlying(10e18);
        assertEq(cETH.balanceOf(user), 0);
        assertEq(ethBalanceBeforeMint, user.balance);
    }

    function testBorrow() public {
        cDAI = new CErc20Immutable(
            dai,
            LendtrollerInterface(unitroller),
            gauge,
            InterestRateModel(address(deployments.jumpRateModel())),
            _ONE,
            "cDAI",
            "cDAI",
            18,
            payable(admin)
        );
        cETH = new CEther(
            LendtrollerInterface(unitroller),
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
        Lendtroller(unitroller)._supportMarket(CToken(address(cDAI)));
        vm.prank(admin);
        Lendtroller(unitroller)._supportMarket(CToken(address(cETH)));
        // set collateral factor
        vm.prank(admin);
        Lendtroller(unitroller)._setCollateralFactor(CToken(address(cDAI)), 5e17);
        vm.prank(admin);
        Lendtroller(unitroller)._setCollateralFactor(CToken(address(cETH)), 5e17);

        // enter markets
        vm.prank(user);
        address[] memory markets = new address[](2);
        markets[0] = address(cDAI);
        markets[1] = address(cETH);
        LendtrollerInterface(unitroller).enterMarkets(markets);

        // mint cDAI
        IERC20(dai).approve(address(cDAI), 100e18);
        assertTrue(cDAI.mint(100e18));

        // mint cETH
        cETH.mint{ value: 10e18 }();

        uint256 daiBalanceBeforeBorrow = IERC20(dai).balanceOf(user);
        uint256 ethBalanceBeforeBorrow = user.balance;

        // borrow DAI
        cDAI.borrow(50e18);
        assertEq(cDAI.balanceOf(user), 100e18);
        assertEq(daiBalanceBeforeBorrow + 50e18, IERC20(dai).balanceOf(user));

        // borrow ETH
        cETH.borrow(5e18);
        assertEq(cETH.balanceOf(user), 10e18);
        assertEq(ethBalanceBeforeBorrow + 5e18, user.balance);
    }

    function testRepayBorrow() public {
        cDAI = new CErc20Immutable(
            dai,
            LendtrollerInterface(unitroller),
            gauge,
            InterestRateModel(address(deployments.jumpRateModel())),
            _ONE,
            "cDAI",
            "cDAI",
            18,
            payable(admin)
        );
        cETH = new CEther(
            LendtrollerInterface(unitroller),
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
        Lendtroller(unitroller)._supportMarket(CToken(address(cDAI)));
        vm.prank(admin);
        Lendtroller(unitroller)._supportMarket(CToken(address(cETH)));
        // set collateral factor
        vm.prank(admin);
        Lendtroller(unitroller)._setCollateralFactor(CToken(address(cDAI)), 5e17);
        vm.prank(admin);
        Lendtroller(unitroller)._setCollateralFactor(CToken(address(cETH)), 5e17);

        // enter markets
        vm.prank(user);
        address[] memory markets = new address[](2);
        markets[0] = address(cDAI);
        markets[1] = address(cETH);
        LendtrollerInterface(unitroller).enterMarkets(markets);

        // mint cDAI
        IERC20(dai).approve(address(cDAI), 100e18);
        assertTrue(cDAI.mint(100e18));

        // mint cETH
        cETH.mint{ value: 10e18 }();

        uint256 daiBalanceBeforeBorrow = IERC20(dai).balanceOf(user);
        uint256 ethBalanceBeforeBorrow = user.balance;

        // borrow DAI
        cDAI.borrow(50e18);
        assertEq(cDAI.balanceOf(user), 100e18);
        assertEq(daiBalanceBeforeBorrow + 50e18, IERC20(dai).balanceOf(user));

        // borrow ETH
        cETH.borrow(5e18);
        assertEq(cETH.balanceOf(user), 10e18);
        assertEq(ethBalanceBeforeBorrow + 5e18, user.balance);

        // repay DAI
        IERC20(dai).approve(address(cDAI), 50e18);
        cDAI.repayBorrow(50e18);
        assertEq(daiBalanceBeforeBorrow, IERC20(dai).balanceOf(user));

        // repay ETH
        cETH.repayBorrow{ value: 5e18 }();
        assertEq(ethBalanceBeforeBorrow, user.balance);
    }

    function testRepayBorrowBehalf() public {
        cDAI = new CErc20Immutable(
            dai,
            LendtrollerInterface(unitroller),
            gauge,
            InterestRateModel(address(deployments.jumpRateModel())),
            _ONE,
            "cDAI",
            "cDAI",
            18,
            payable(admin)
        );
        cETH = new CEther(
            LendtrollerInterface(unitroller),
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
        Lendtroller(unitroller)._supportMarket(CToken(address(cDAI)));
        vm.prank(admin);
        Lendtroller(unitroller)._supportMarket(CToken(address(cETH)));
        // set collateral factor
        vm.prank(admin);
        Lendtroller(unitroller)._setCollateralFactor(CToken(address(cDAI)), 5e17);
        vm.prank(admin);
        Lendtroller(unitroller)._setCollateralFactor(CToken(address(cETH)), 5e17);

        // enter markets
        vm.prank(user);
        address[] memory markets = new address[](2);
        markets[0] = address(cDAI);
        markets[1] = address(cETH);
        LendtrollerInterface(unitroller).enterMarkets(markets);

        // mint cDAI
        IERC20(dai).approve(address(cDAI), 100e18);
        assertTrue(cDAI.mint(100e18));

        // mint cETH
        cETH.mint{ value: 10e18 }();

        uint256 daiBalanceBeforeBorrow = IERC20(dai).balanceOf(user);
        uint256 ethBalanceBeforeBorrow = user.balance;

        // borrow DAI
        cDAI.borrow(50e18);
        assertEq(cDAI.balanceOf(user), 100e18);
        assertEq(daiBalanceBeforeBorrow + 50e18, IERC20(dai).balanceOf(user));

        // borrow ETH
        cETH.borrow(5e18);
        assertEq(cETH.balanceOf(user), 10e18);
        assertEq(ethBalanceBeforeBorrow + 5e18, user.balance);

        // repay DAI
        IERC20(dai).approve(address(cDAI), 50e18);
        cDAI.repayBorrowBehalf(user, 50e18);
        assertEq(daiBalanceBeforeBorrow, IERC20(dai).balanceOf(user));

        // repay ETH
        cETH.repayBorrowBehalf{ value: 5e18 }(user);
        assertEq(ethBalanceBeforeBorrow, user.balance);
    }

    function testLiquidateBorrow() public {
        cDAI = new CErc20Immutable(
            dai,
            LendtrollerInterface(unitroller),
            gauge,
            InterestRateModel(address(deployments.jumpRateModel())),
            _ONE,
            "cDAI",
            "cDAI",
            18,
            payable(admin)
        );
        cETH = new CEther(
            LendtrollerInterface(unitroller),
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
        Lendtroller(unitroller)._supportMarket(CToken(address(cDAI)));
        vm.prank(admin);
        Lendtroller(unitroller)._supportMarket(CToken(address(cETH)));
        // set collateral factor
        vm.prank(admin);
        Lendtroller(unitroller)._setCollateralFactor(CToken(address(cDAI)), 5e17);
        vm.prank(admin);
        Lendtroller(unitroller)._setCollateralFactor(CToken(address(cETH)), 5e17);

        // enter markets
        vm.prank(user);
        address[] memory markets = new address[](2);
        markets[0] = address(cDAI);
        markets[1] = address(cETH);
        LendtrollerInterface(unitroller).enterMarkets(markets);

        // mint cDAI
        IERC20(dai).approve(address(cDAI), 100e18);
        assertTrue(cDAI.mint(100e18));

        // mint cETH
        cETH.mint{ value: 10e18 }();

        // borrow DAI
        cDAI.borrow(50e18);
        assertEq(cDAI.balanceOf(user), 100e18);

        // borrow ETH
        cETH.borrow(5e18);
        assertEq(cETH.balanceOf(user), 10e18);

        // set collateral factor
        vm.prank(admin);
        Lendtroller(unitroller)._setCollateralFactor(CToken(address(cDAI)), 4e17);
        vm.prank(admin);
        Lendtroller(unitroller)._setCollateralFactor(CToken(address(cETH)), 4e17);

        // liquidateBorrow DAI
        vm.prank(liquidator);
        IERC20(dai).approve(address(cDAI), 100e18);
        vm.prank(liquidator);
        cDAI.liquidateBorrow(user, 12e18, CTokenInterface(cDAI));
        assertEq(cDAI.balanceOf(liquidator), 5832000000000000000);

        // liquidateBorrow ETH
        vm.prank(liquidator);
        cETH.liquidateBorrow{ value: 12e17 }(user, CToken(cETH));

        assertEq(cETH.balanceOf(liquidator), 583200000000000000);
    }
}
