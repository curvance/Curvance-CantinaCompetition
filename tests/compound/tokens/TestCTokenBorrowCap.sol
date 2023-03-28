// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "contracts/compound/Comptroller/Comptroller.sol";
import "contracts/compound/Comptroller/ComptrollerInterface.sol";
import "contracts/compound/Token/CErc20Immutable.sol";
import "contracts/compound/Oracle/SimplePriceOracle.sol";
import "contracts/compound/InterestRateModel/InterestRateModel.sol";
import { GaugePool } from "contracts/gauge/GaugePool.sol";

import "tests/compound/deploy.sol";
import "tests/lib/DSTestPlus.sol";
import "hardhat/console.sol";

contract User {}

contract TestCTokenBorrowCap is DSTestPlus {
    address public dai = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    address public admin;
    address public user;
    address public liquidator;
    DeployCompound public deployments;
    address public unitroller;
    CErc20Immutable public cDAI;
    SimplePriceOracle public priceOracle;
    address gauge;

    function setUp() public {
        deployments = new DeployCompound();
        deployments.makeCompound();
        unitroller = address(deployments.unitroller());
        priceOracle = SimplePriceOracle(deployments.priceOracle());
        priceOracle.setDirectPrice(dai, 1e18);

        admin = deployments.admin();
        user = address(this);
        liquidator = address(new User());

        // prepare 200K DAI
        hevm.store(dai, keccak256(abi.encodePacked(uint256(uint160(user)), uint256(2))), bytes32(uint256(200000e18)));
        hevm.store(
            dai,
            keccak256(abi.encodePacked(uint256(uint160(liquidator)), uint256(2))),
            bytes32(uint256(200000e18))
        );

        gauge = address(new GaugePool(address(0), unitroller));
    }

    function testBorrowCap() public {
        cDAI = new CErc20Immutable(
            dai,
            ComptrollerInterface(unitroller),
            gauge,
            InterestRateModel(address(deployments.jumpRateModel())),
            1e18,
            "cDAI",
            "cDAI",
            18,
            payable(admin)
        );
        // support market
        hevm.prank(admin);
        Comptroller(unitroller)._supportMarket(CToken(address(cDAI)));

        // enter markets
        hevm.prank(user);
        address[] memory markets = new address[](1);
        markets[0] = address(cDAI);
        ComptrollerInterface(unitroller).enterMarkets(markets);

        // set borrow cap to 49
        hevm.prank(admin);
        Comptroller(unitroller)._setBorrowCapGuardian(admin);
        hevm.prank(admin);
        CToken[] memory cTokens = new CToken[](1);
        cTokens[0] = cDAI;
        uint256[] memory borrowCapAmounts = new uint256[](1);
        borrowCapAmounts[0] = 49e18;
        Comptroller(unitroller)._setMarketBorrowCaps(cTokens, borrowCapAmounts);

        // approve
        IERC20(dai).approve(address(cDAI), 100e18);

        // mint
        assertTrue(cDAI.mint(100e18));
        assertEq(cDAI.balanceOf(user), 100e18);

        // can't borrow 50
        hevm.expectRevert(bytes4(keccak256("BorrowCapReached()"))); // Update: we now revert
        cDAI.borrow(50e18);

        // increase borrow cap to 51
        hevm.prank(admin);
        borrowCapAmounts[0] = 51e18;
        Comptroller(unitroller)._setMarketBorrowCaps(cTokens, borrowCapAmounts);

        uint256 balanceBeforeBorrow = IERC20(dai).balanceOf(user);
        // can borrow 50
        cDAI.borrow(50e18);
        assertEq(cDAI.balanceOf(user), 100e18);
        assertEq(balanceBeforeBorrow + 50e18, IERC20(dai).balanceOf(user));
    }
}
