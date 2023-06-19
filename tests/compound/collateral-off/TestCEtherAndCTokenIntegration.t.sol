// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "contracts/compound/Comptroller/Comptroller.sol";
import "contracts/compound/Comptroller/ComptrollerInterface.sol";
import "contracts/compound/Token/CErc20Immutable.sol";
import "contracts/compound/Token/CEther.sol";
import "contracts/compound/Oracle/SimplePriceOracle.sol";
import "contracts/compound/InterestRateModel/InterestRateModel.sol";
import { GaugePool } from "contracts/gauge/GaugePool.sol";

import "tests/compound/deploy.sol";
import "tests/utils/TestBase.sol";
import "forge-std/console.sol";

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

    function testUserCollateralOffAndCannotBorrow() public {
        cDAI = new CErc20Immutable(
            dai,
            ComptrollerInterface(unitroller),
            gauge,
            InterestRateModel(address(deployments.jumpRateModel())),
            _ONE,
            "cDAI",
            "cDAI",
            18,
            payable(admin)
        );
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
        Comptroller(unitroller)._supportMarket(CToken(address(cDAI)));
        vm.prank(admin);
        Comptroller(unitroller)._supportMarket(CToken(address(cETH)));
        // set collateral factor
        vm.prank(admin);
        Comptroller(unitroller)._setCollateralFactor(CToken(address(cDAI)), 5e17);
        vm.prank(admin);
        Comptroller(unitroller)._setCollateralFactor(CToken(address(cETH)), 5e17);

        // enter markets
        vm.prank(user);
        address[] memory markets = new address[](2);
        markets[0] = address(cDAI);
        markets[1] = address(cETH);
        ComptrollerInterface(unitroller).enterMarkets(markets);

        // mint cDAI
        IERC20(dai).approve(address(cDAI), 100e18);
        assertTrue(cDAI.mint(100e18));

        // mint cETH
        cETH.mint{ value: 10e18 }();

        CToken[] memory cTokens = new CToken[](2);
        cTokens[0] = cDAI;
        cTokens[1] = cETH;
        vm.prank(user);
        Comptroller(unitroller).setUserDisableCollateral(cTokens, true);

        vm.expectRevert(ComptrollerInterface.InsufficientLiquidity.selector);
        cDAI.borrow(50e18);
    }

    function testCollateralOffAndCannotBorrow() public {
        cDAI = new CErc20Immutable(
            dai,
            ComptrollerInterface(unitroller),
            gauge,
            InterestRateModel(address(deployments.jumpRateModel())),
            _ONE,
            "cDAI",
            "cDAI",
            18,
            payable(admin)
        );
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
        Comptroller(unitroller)._supportMarket(CToken(address(cDAI)));
        vm.prank(admin);
        Comptroller(unitroller)._supportMarket(CToken(address(cETH)));
        // set collateral factor
        vm.prank(admin);
        Comptroller(unitroller)._setCollateralFactor(CToken(address(cDAI)), 5e17);
        vm.prank(admin);
        Comptroller(unitroller)._setCollateralFactor(CToken(address(cETH)), 5e17);

        // enter markets
        vm.prank(user);
        address[] memory markets = new address[](2);
        markets[0] = address(cDAI);
        markets[1] = address(cETH);
        ComptrollerInterface(unitroller).enterMarkets(markets);

        // mint cDAI
        IERC20(dai).approve(address(cDAI), 100e18);
        assertTrue(cDAI.mint(100e18));

        // mint cETH
        cETH.mint{ value: 10e18 }();

        CToken[] memory cTokens = new CToken[](2);
        cTokens[0] = cDAI;
        cTokens[1] = cETH;
        vm.prank(admin);
        Comptroller(unitroller)._setDisableCollateral(cTokens, true);

        vm.expectRevert(ComptrollerInterface.InsufficientLiquidity.selector);
        cDAI.borrow(50e18);
    }

    function testCannotDisableCollateralWhenNotSafe() public {
        cDAI = new CErc20Immutable(
            dai,
            ComptrollerInterface(unitroller),
            gauge,
            InterestRateModel(address(deployments.jumpRateModel())),
            _ONE,
            "cDAI",
            "cDAI",
            18,
            payable(admin)
        );
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
        Comptroller(unitroller)._supportMarket(CToken(address(cDAI)));
        vm.prank(admin);
        Comptroller(unitroller)._supportMarket(CToken(address(cETH)));
        // set collateral factor
        vm.prank(admin);
        Comptroller(unitroller)._setCollateralFactor(CToken(address(cDAI)), 5e17);
        vm.prank(admin);
        Comptroller(unitroller)._setCollateralFactor(CToken(address(cETH)), 5e17);

        // enter markets
        vm.prank(user);
        address[] memory markets = new address[](2);
        markets[0] = address(cDAI);
        markets[1] = address(cETH);
        ComptrollerInterface(unitroller).enterMarkets(markets);

        // mint cDAI
        IERC20(dai).approve(address(cDAI), 100e18);
        assertTrue(cDAI.mint(100e18));

        // mint cETH
        cETH.mint{ value: 10e18 }();

        // borrow DAI
        cDAI.borrow(50e18);

        CToken[] memory cTokens = new CToken[](2);
        cTokens[0] = cDAI;
        cTokens[1] = cETH;
        vm.prank(user);
        vm.expectRevert(ComptrollerInterface.InsufficientLiquidity.selector);
        Comptroller(unitroller).setUserDisableCollateral(cTokens, true);
    }
}
