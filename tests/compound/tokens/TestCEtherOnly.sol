// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "contracts/compound/Comptroller.sol";
import "contracts/compound/Token/CEther.sol";
import "contracts/compound/Errors.sol";
import "contracts/compound/SimplePriceOracle.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "contracts/compound/ComptrollerInterface.sol";
import "contracts/compound/InterestRateModel/InterestRateModel.sol";

import "tests/compound/deploy.sol";
import "tests/lib/DSTestPlus.sol";
import "hardhat/console.sol";

contract User {}

contract TestCEther is DSTestPlus {
    address public admin;
    address public user;
    address public liquidator;
    DeployCompound public deployments;
    address public unitroller;
    CEther public cETH;
    SimplePriceOracle public priceOracle;

    receive() external payable {}

    fallback() external payable {}

    function setUp() public {
        deployments = new DeployCompound();
        deployments.makeCompound();
        unitroller = address(deployments.unitroller());
        priceOracle = SimplePriceOracle(deployments.priceOracle());
        priceOracle.setDirectPrice(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, 1e18);

        admin = deployments.admin();
        user = address(this);
        liquidator = address(new User());

        // prepare 200K ETH
        hevm.deal(user, 200000e18);
        hevm.deal(liquidator, 200000e18);
    }

    function testInitialize() public {
        cETH = new CEther(
            ComptrollerInterface(unitroller),
            InterestRateModel(address(deployments.jumpRateModel())),
            1e18,
            "cETH",
            "cETH",
            18,
            payable(admin)
        );
    }

    function testMint() public {
        cETH = new CEther(
            ComptrollerInterface(unitroller),
            InterestRateModel(address(deployments.jumpRateModel())),
            1e18,
            "cETH",
            "cETH",
            18,
            payable(admin)
        );
        // support market
        hevm.prank(admin);
        Comptroller(unitroller)._supportMarket(CToken(address(cETH)));

        // enter markets
        hevm.prank(user);
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
            InterestRateModel(address(deployments.jumpRateModel())),
            1e18,
            "cETH",
            "cETH",
            18,
            payable(admin)
        );
        // support market
        hevm.prank(admin);
        Comptroller(unitroller)._supportMarket(CToken(address(cETH)));

        // enter markets
        hevm.prank(user);
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
            InterestRateModel(address(deployments.jumpRateModel())),
            1e18,
            "cETH",
            "cETH",
            18,
            payable(admin)
        );
        // support market
        hevm.prank(admin);
        Comptroller(unitroller)._supportMarket(CToken(address(cETH)));

        // enter markets
        hevm.prank(user);
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
            InterestRateModel(address(deployments.jumpRateModel())),
            1e18,
            "cETH",
            "cETH",
            18,
            payable(admin)
        );
        // support market
        hevm.prank(admin);
        Comptroller(unitroller)._supportMarket(CToken(address(cETH)));

        // enter markets
        hevm.prank(user);
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
            InterestRateModel(address(deployments.jumpRateModel())),
            1e18,
            "cETH",
            "cETH",
            18,
            payable(admin)
        );
        // support market
        hevm.prank(admin);
        Comptroller(unitroller)._supportMarket(CToken(address(cETH)));

        // enter markets
        hevm.prank(user);
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
            InterestRateModel(address(deployments.jumpRateModel())),
            1e18,
            "cETH",
            "cETH",
            18,
            payable(admin)
        );
        // support market
        hevm.prank(admin);
        Comptroller(unitroller)._supportMarket(CToken(address(cETH)));

        // enter markets
        hevm.prank(user);
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
            InterestRateModel(address(deployments.jumpRateModel())),
            1e18,
            "cETH",
            "cETH",
            18,
            payable(admin)
        );
        // support market
        hevm.prank(admin);
        Comptroller(unitroller)._supportMarket(CToken(address(cETH)));

        // enter markets
        hevm.prank(user);
        address[] memory markets = new address[](1);
        markets[0] = address(cETH);
        ComptrollerInterface(unitroller).enterMarkets(markets);

        // mint
        cETH.mint{ value: 100e18 }();
        assertEq(cETH.balanceOf(user), 100e18);

        // borrow
        cETH.borrow(50e18);
        assertEq(cETH.balanceOf(user), 100e18);

        // price dump
        priceOracle.setDirectPrice(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, 6e17);

        // liquidateBorrow
        hevm.prank(liquidator);
        cETH.liquidateBorrow{ value: 12e18 }(user, CToken(cETH));

        assertEq(cETH.balanceOf(liquidator), 5832000000000000000);
    }
}
