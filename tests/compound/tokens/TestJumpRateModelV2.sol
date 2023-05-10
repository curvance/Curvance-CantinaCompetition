// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "contracts/compound/Cve.sol";
import "contracts/compound/CompRewards/CompRewards.sol";
import "contracts/compound/Comptroller/Comptroller.sol";
import "contracts/compound/Comptroller/ComptrollerInterface.sol";
import "contracts/compound/Token/CErc20Immutable.sol";
import "contracts/compound/Oracle/SimplePriceOracle.sol";
import "contracts/compound/InterestRateModel/JumpRateModelV2.sol";
import "contracts/compound/InterestRateModel/InterestRateModel.sol";
import { GaugePool } from "contracts/gauge/GaugePool.sol";

import "tests/compound/deploy.sol";
import "tests/lib/DSTestPlus.sol";
import "hardhat/console.sol";

contract User {}

contract TestJumpRateModelV2 is DSTestPlus {
    address public dai = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    address public admin;
    address public user;
    address public liquidator;
    DeployCompound public deployments;
    address public unitroller;
    CompRewards public compRewards;
    Cve public cve;
    CErc20Immutable public cDAI;
    SimplePriceOracle public priceOracle;
    address interestRateModel;
    address public pot = address(0x197E90f9FAD81970bA7976f33CbD77088E5D7cf7);
    address public jug = address(0x19c0976f590D67707E62397C87829d896Dc0f1F1);
    address gauge;

    function setUp() public {
        deployments = new DeployCompound();
        deployments.makeCompound();
        unitroller = address(deployments.unitroller());
        compRewards = deployments.compRewards();
        cve = deployments.cve();
        priceOracle = SimplePriceOracle(deployments.priceOracle());
        priceOracle.setDirectPrice(dai, 1e18);

        admin = deployments.admin();
        user = address(this);
        liquidator = address(new User());

        interestRateModel = address(new JumpRateModelV2(1e17, 1e17, 1e17, 5e17, admin));

        // prepare 200K DAI
        hevm.store(dai, keccak256(abi.encodePacked(uint256(uint160(user)), uint256(2))), bytes32(uint256(200000e18)));
        hevm.store(
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
            InterestRateModel(interestRateModel),
            1e18,
            "cDAI",
            "cDAI",
            18,
            payable(admin)
        );
        // support market
        hevm.prank(admin);
        Comptroller(unitroller)._supportMarket(CToken(address(cDAI)));
        // set collateral factor
        hevm.prank(admin);
        Comptroller(unitroller)._setCollateralFactor(CToken(address(cDAI)), 5e17);
        hevm.prank(admin);
        compRewards._setCveSpeed(CToken(cDAI), 1e16); // 0.01 CVE per block

        // enter markets
        hevm.prank(user);
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

        hevm.roll(block.number + 1000);
        compRewards.claimCve(holders, cTokens, false, true);
        uint256 cveBalance = cve.balanceOf(user);
        assertEq(cveBalance, 1e16 * 1000);
    }

    function testBorrowIndex() public {
        cDAI = new CErc20Immutable(
            dai,
            ComptrollerInterface(unitroller),
            gauge,
            InterestRateModel(interestRateModel),
            1e18,
            "cDAI",
            "cDAI",
            18,
            payable(admin)
        );
        // support market
        hevm.prank(admin);
        Comptroller(unitroller)._supportMarket(CToken(address(cDAI)));
        // set collateral factor
        hevm.prank(admin);
        Comptroller(unitroller)._setCollateralFactor(CToken(address(cDAI)), 5e17);
        hevm.prank(admin);
        compRewards._setCveSpeed(CToken(cDAI), 1e16); // 0.01 CVE per block

        // enter markets
        hevm.prank(user);
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

        hevm.roll(block.number + 1000);
        compRewards.claimCve(holders, cTokens, true, false);
        uint256 cveBalance = cve.balanceOf(user);
        assertEq(cveBalance, 1e16 * 1000);
    }
}
