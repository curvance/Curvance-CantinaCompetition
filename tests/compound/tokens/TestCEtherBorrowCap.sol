// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "contracts/compound/Comptroller/Comptroller.sol";
import "contracts/compound/Comptroller/ComptrollerInterface.sol";
import "contracts/compound/Token/CEther.sol";
import "contracts/compound/Oracle/SimplePriceOracle.sol";
import "contracts/compound/InterestRateModel/InterestRateModel.sol";
import { GaugePool } from "contracts/gauge/GaugePool.sol";

import "tests/compound/deploy.sol";
import "tests/lib/DSTestPlus.sol";
import "hardhat/console.sol";

contract User {}

contract TestCEtherBorrowCap is DSTestPlus {
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
        priceOracle.setDirectPrice(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, 1e18);

        admin = deployments.admin();
        user = address(this);
        liquidator = address(new User());

        // prepare 200K ETH
        hevm.deal(user, 200000e18);
        hevm.deal(liquidator, 200000e18);

        gauge = address(new GaugePool(address(0), unitroller));
    }

    function testBorrowCap() public {
        cETH = new CEther(
            ComptrollerInterface(unitroller),
            gauge,
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
        // set collateral factor
        hevm.prank(admin);
        Comptroller(unitroller)._setCollateralFactor(CToken(address(cETH)), 5e17);

        // enter markets
        hevm.prank(user);
        address[] memory markets = new address[](1);
        markets[0] = address(cETH);
        ComptrollerInterface(unitroller).enterMarkets(markets);

        // set borrow cap to 49
        hevm.prank(admin);
        Comptroller(unitroller)._setBorrowCapGuardian(admin);
        hevm.prank(admin);
        CToken[] memory cTokens = new CToken[](1);
        cTokens[0] = CToken(address(cETH));
        uint256[] memory borrowCapAmounts = new uint256[](1);
        borrowCapAmounts[0] = 49e18;
        Comptroller(unitroller)._setMarketBorrowCaps(cTokens, borrowCapAmounts);

        // mint
        cETH.mint{ value: 100e18 }();
        assertEq(cETH.balanceOf(user), 100e18);

        // can't borrow 50
        hevm.expectRevert(bytes4(keccak256("BorrowCapReached()"))); // Update: we now revert
        cETH.borrow(50e18);

        // increase borrow cap to 51
        hevm.prank(admin);
        borrowCapAmounts[0] = 51e18;
        Comptroller(unitroller)._setMarketBorrowCaps(cTokens, borrowCapAmounts);

        uint256 balanceBeforeBorrow = user.balance;
        // borrow
        cETH.borrow(50e18);
        assertEq(cETH.balanceOf(user), 100e18);
        assertEq(balanceBeforeBorrow + 50e18, user.balance);
    }
}
