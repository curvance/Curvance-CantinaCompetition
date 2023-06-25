// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "contracts/token/CVE.sol";
import "contracts/market/CompRewards/CompRewards.sol";
import "contracts/market/lendtroller/Lendtroller.sol";
import "contracts/market/lendtroller/LendtrollerInterface.sol";
import "contracts/market/Token/CErc20Immutable.sol";
import "contracts/market/Oracle/SimplePriceOracle.sol";
import "contracts/market/InterestRateModel/InterestRateModel.sol";
import { GaugePool } from "contracts/gauge/GaugePool.sol";

import "tests/compound/deploy.sol";
import "tests/utils/TestBase.sol";

contract User {}

contract TestCompRewards is TestBase {
    address public dai = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    address public admin;
    address public user;
    address public liquidator;
    DeployCompound public deployments;
    address public unitroller;
    CompRewards public compRewards;
    CVE public cve;
    CErc20Immutable public cDAI;
    SimplePriceOracle public priceOracle;
    address gauge;

    function setUp() public {
        _fork();

        deployments = new DeployCompound();
        deployments.makeCompound();
        unitroller = address(deployments.unitroller());
        compRewards = deployments.compRewards();
        cve = deployments.cve();
        priceOracle = SimplePriceOracle(deployments.priceOracle());
        priceOracle.setDirectPrice(dai, _ONE);

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

        gauge = address(new GaugePool(address(0), address(0), unitroller));
    }

    function testSupplyIndex() public {
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
        // support market
        vm.prank(admin);
        Comptroller(unitroller)._supportMarket(CToken(address(cDAI)));
        vm.prank(admin);
        Comptroller(unitroller)._setCollateralFactor(CToken(address(cDAI)), 5e17);
        vm.prank(admin);
        compRewards._setCveSpeed(CToken(cDAI), 1e16); // 0.01 CVE per block

        // enter markets
        vm.prank(user);
        address[] memory markets = new address[](1);
        markets[0] = address(cDAI);
        ComptrollerInterface(unitroller).enterMarkets(markets);

        // approve
        IERC20(dai).approve(address(cDAI), 100e18);

        // mint
        assertTrue(cDAI.mint(100e18));
        assertGt(cDAI.balanceOf(user), 0);

        address[] memory holders = new address[](1);
        holders[0] = user;
        CToken[] memory cTokens = new CToken[](1);
        cTokens[0] = CToken(cDAI);

        vm.roll(block.number + 1000);
        compRewards.claimCve(holders, cTokens, false, true);
        uint256 cveBalance = cve.balanceOf(user);
        assertEq(cveBalance, 1e16 * 1000);
    }

    function testBorrowIndex() public {
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
        // support market
        vm.prank(admin);
        Comptroller(unitroller)._supportMarket(CToken(address(cDAI)));
        vm.prank(admin);
        Comptroller(unitroller)._setCollateralFactor(CToken(address(cDAI)), 5e17);
        vm.prank(admin);
        compRewards._setCveSpeed(CToken(cDAI), 1e16); // 0.01 CVE per block

        // enter markets
        vm.prank(user);
        address[] memory markets = new address[](1);
        markets[0] = address(cDAI);
        ComptrollerInterface(unitroller).enterMarkets(markets);

        // approve
        IERC20(dai).approve(address(cDAI), 100e18);

        // mint
        assertTrue(cDAI.mint(100e18));
        assertEq(cDAI.balanceOf(user), 100e18);

        uint256 balanceBeforeBorrow = IERC20(dai).balanceOf(user);
        // borrow
        cDAI.borrow(50e18);
        assertEq(cDAI.balanceOf(user), 100e18);
        assertEq(balanceBeforeBorrow + 50e18, IERC20(dai).balanceOf(user));

        address[] memory holders = new address[](1);
        holders[0] = user;
        CToken[] memory cTokens = new CToken[](1);
        cTokens[0] = CToken(cDAI);

        vm.roll(block.number + 1000);
        compRewards.claimCve(holders, cTokens, true, false);
        uint256 cveBalance = cve.balanceOf(user);
        assertEq(cveBalance, 1e16 * 1000);
    }
}
