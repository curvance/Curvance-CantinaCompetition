// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "contracts/compound/Comptroller/Comptroller.sol";
import "contracts/compound/Comptroller/ComptrollerInterface.sol";
import "contracts/compound/Token/CErc20Immutable.sol";
import "contracts/compound/Token/CEther.sol";
import "contracts/compound/Oracle/SimplePriceOracle.sol";
import "contracts/compound/InterestRateModel/InterestRateModel.sol";
import { GaugePool } from "contracts/gauge/GaugePool.sol";

import "tests/compound/deploy.sol";
import "tests/lib/DSTestPlus.sol";
import "hardhat/console.sol";

contract User {
    receive() external payable {}

    fallback() external payable {}
}

contract TestCTokenAndCEther is DSTestPlus {
    address public dai = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    address public admin;
    address public user1;
    address public user2;
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
        priceOracle.setDirectPrice(dai, 1e18);
        priceOracle.setDirectPrice(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, 2e18);

        admin = deployments.admin();
        user1 = address(this);
        user2 = address(new User());
        liquidator = address(new User());

        // prepare 200K DAI
        hevm.store(dai, keccak256(abi.encodePacked(uint256(uint160(user1)), uint256(2))), bytes32(uint256(200000e18)));
        hevm.store(dai, keccak256(abi.encodePacked(uint256(uint160(user2)), uint256(2))), bytes32(uint256(200000e18)));
        hevm.store(
            dai,
            keccak256(abi.encodePacked(uint256(uint160(liquidator)), uint256(2))),
            bytes32(uint256(200000e18))
        );
        // prepare 200K ETH
        hevm.deal(user1, 200000e18);
        hevm.deal(user2, 200000e18);
        hevm.deal(liquidator, 200000e18);

        gauge = address(new GaugePool(address(0), address(0), unitroller));
    }

    function testInitialize() public {
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
    }

    // function testMint() public {
    //     cDAI = new CErc20Immutable(
    //         dai,
    //         ComptrollerInterface(unitroller),
    //         InterestRateModel(address(deployments.jumpRateModel())),
    //         1e18,
    //         "cDAI",
    //         "cDAI",
    //         18,
    //         payable(admin)
    //     );
    //     cETH = new CEther(
    //         ComptrollerInterface(unitroller),
    //         InterestRateModel(address(deployments.jumpRateModel())),
    //         1e18,
    //         "cETH",
    //         "cETH",
    //         18,
    //         payable(admin)
    //     );
    //     // support market
    //     hevm.prank(admin);
    //     Comptroller(unitroller)._supportMarket(CToken(address(cDAI)));
    //     hevm.prank(admin);
    //     Comptroller(unitroller)._supportMarket(CToken(address(cETH)));

    //     // user1 enter markets
    //     hevm.prank(user1);
    //     address[] memory markets = new address[](2);
    //     markets[0] = address(cDAI);
    //     markets[1] = address(cETH);
    //     ComptrollerInterface(unitroller).enterMarkets(markets);

    //     // user1 approve
    //     hevm.prank(user1);
    //     IERC20(dai).approve(address(cDAI), 100e18);

    //     // user1 mint
    //     hevm.prank(user1);
    //     assertTrue(cDAI.mint(100e18));
    //     assertGt(cDAI.balanceOf(user1), 0);

    //     // user2 enter market
    //     hevm.prank(user2);
    //     ComptrollerInterface(unitroller).enterMarkets(markets);

    //     // user2 mint
    //     hevm.prank(user2);
    //     cETH.mint{ value: 100e18 }();
    //     assertGt(cETH.balanceOf(user2), 0);
    // }

    function testRedeem() public {
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
        Comptroller(unitroller)._supportMarket(CToken(address(cDAI)));
        hevm.prank(admin);
        Comptroller(unitroller)._supportMarket(CToken(address(cETH)));
        // set collateral factor
        hevm.prank(admin);
        Comptroller(unitroller)._setCollateralFactor(CToken(address(cDAI)), 5e17);
        hevm.prank(admin);
        Comptroller(unitroller)._setCollateralFactor(CToken(address(cETH)), 5e17);

        // user1 enter markets
        hevm.prank(user1);
        address[] memory markets = new address[](2);
        markets[0] = address(cDAI);
        markets[1] = address(cETH);
        ComptrollerInterface(unitroller).enterMarkets(markets);

        // auser1 pprove
        hevm.prank(user1);
        IERC20(dai).approve(address(cDAI), 100e18);

        uint256 balanceBeforeMint = IERC20(dai).balanceOf(user1);
        // user1 mint
        hevm.prank(user1);
        assertTrue(cDAI.mint(100e18));
        assertEq(cDAI.balanceOf(user1), 100e18);
        assertGt(balanceBeforeMint, IERC20(dai).balanceOf(user1));

        // user1 redeem
        hevm.prank(user1);
        cDAI.redeem(100e18);
        assertEq(cDAI.balanceOf(user1), 0);
        assertEq(balanceBeforeMint, IERC20(dai).balanceOf(user1));

        // user2 enter markets
        hevm.prank(user2);
        ComptrollerInterface(unitroller).enterMarkets(markets);

        balanceBeforeMint = user2.balance;
        // user2 mint
        hevm.prank(user2);
        cETH.mint{ value: 100e18 }();
        assertEq(cETH.balanceOf(user2), 100e18);
        assertGt(balanceBeforeMint, user2.balance);

        // user2 redeem
        hevm.prank(user2);
        cETH.redeem(100e18);
        assertEq(cETH.balanceOf(user2), 0);
        assertEq(balanceBeforeMint, user2.balance);
    }

    function testRedeemUnderlying() public {
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
        Comptroller(unitroller)._supportMarket(CToken(address(cDAI)));
        hevm.prank(admin);
        Comptroller(unitroller)._supportMarket(CToken(address(cETH)));
        // set collateral factor
        hevm.prank(admin);
        Comptroller(unitroller)._setCollateralFactor(CToken(address(cDAI)), 5e17);
        hevm.prank(admin);
        Comptroller(unitroller)._setCollateralFactor(CToken(address(cETH)), 5e17);

        // user1 enter markets
        hevm.prank(user1);
        address[] memory markets = new address[](2);
        markets[0] = address(cDAI);
        markets[1] = address(cETH);
        ComptrollerInterface(unitroller).enterMarkets(markets);

        // user1 approve
        hevm.prank(user1);
        IERC20(dai).approve(address(cDAI), 100e18);

        uint256 balanceBeforeMint = IERC20(dai).balanceOf(user1);
        // user1 mint
        hevm.prank(user1);
        assertTrue(cDAI.mint(100e18));
        assertEq(cDAI.balanceOf(user1), 100e18);
        assertGt(balanceBeforeMint, IERC20(dai).balanceOf(user1));

        // redeem
        hevm.prank(user1);
        cDAI.redeemUnderlying(100e18);
        assertEq(cDAI.balanceOf(user1), 0);
        assertEq(balanceBeforeMint, IERC20(dai).balanceOf(user1));

        // user2 enter markets
        hevm.prank(user2);
        ComptrollerInterface(unitroller).enterMarkets(markets);

        balanceBeforeMint = user2.balance;
        // user2 mint
        hevm.prank(user2);
        cETH.mint{ value: 100e18 }();
        assertEq(cETH.balanceOf(user2), 100e18);
        assertGt(balanceBeforeMint, user2.balance);

        // user2 redeem
        hevm.prank(user2);
        cETH.redeemUnderlying(100e18);
        assertEq(cETH.balanceOf(user2), 0);
        assertEq(balanceBeforeMint, user2.balance);
    }

    function testBorrow() public {
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
        Comptroller(unitroller)._supportMarket(CToken(address(cDAI)));
        hevm.prank(admin);
        Comptroller(unitroller)._supportMarket(CToken(address(cETH)));
        // set collateral factor
        hevm.prank(admin);
        Comptroller(unitroller)._setCollateralFactor(CToken(address(cDAI)), 5e17);
        hevm.prank(admin);
        Comptroller(unitroller)._setCollateralFactor(CToken(address(cETH)), 5e17);

        // user1 enter markets
        hevm.prank(user1);
        address[] memory markets = new address[](2);
        markets[0] = address(cDAI);
        markets[1] = address(cETH);
        ComptrollerInterface(unitroller).enterMarkets(markets);

        // user1 approve
        hevm.prank(user1);
        IERC20(dai).approve(address(cDAI), 100e18);

        // user1 mint
        hevm.prank(user1);
        assertTrue(cDAI.mint(100e18));
        assertEq(cDAI.balanceOf(user1), 100e18);

        // user2 enter markets
        hevm.prank(user2);
        ComptrollerInterface(unitroller).enterMarkets(markets);

        // user2 mint
        hevm.prank(user2);
        cETH.mint{ value: 100e18 }();
        assertEq(cETH.balanceOf(user2), 100e18);

        // user2 borrow
        uint256 balanceBeforeBorrow = IERC20(dai).balanceOf(user2);
        hevm.prank(user2);
        cDAI.borrow(100e18);
        assertEq(cETH.balanceOf(user2), 100e18);
        assertEq(balanceBeforeBorrow + 100e18, IERC20(dai).balanceOf(user2));

        // user1 borrow
        balanceBeforeBorrow = user1.balance;
        hevm.prank(user1);
        cETH.borrow(25e18);
        assertEq(cDAI.balanceOf(user1), 100e18);
        assertEq(balanceBeforeBorrow + 25e18, user1.balance);
    }

    function testBorrow2() public {
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
        Comptroller(unitroller)._supportMarket(CToken(address(cDAI)));
        hevm.prank(admin);
        Comptroller(unitroller)._supportMarket(CToken(address(cETH)));
        // set collateral factor
        hevm.prank(admin);
        Comptroller(unitroller)._setCollateralFactor(CToken(address(cDAI)), 5e17);
        hevm.prank(admin);
        Comptroller(unitroller)._setCollateralFactor(CToken(address(cETH)), 5e17);

        // user1 enter markets
        hevm.prank(user1);
        address[] memory markets = new address[](2);
        markets[0] = address(cDAI);
        markets[1] = address(cETH);
        ComptrollerInterface(unitroller).enterMarkets(markets);

        // user1 approve
        IERC20(dai).approve(address(cDAI), 100e18);

        // user1 mint
        hevm.prank(user1);
        assertTrue(cDAI.mint(100e18));
        assertEq(cDAI.balanceOf(user1), 100e18);

        // user1 enter markets
        ComptrollerInterface(unitroller).enterMarkets(markets);

        // user1 mint
        hevm.prank(user1);
        cETH.mint{ value: 100e18 }();
        assertEq(cETH.balanceOf(user1), 100e18);

        // user1 borrow
        uint256 balanceBeforeBorrow = IERC20(dai).balanceOf(user1);
        hevm.prank(user1);
        cDAI.borrow(100e18);
        assertEq(cETH.balanceOf(user1), 100e18);
        assertEq(balanceBeforeBorrow + 100e18, IERC20(dai).balanceOf(user1));

        // user1 borrow
        balanceBeforeBorrow = user1.balance;
        hevm.prank(user1);
        cETH.borrow(25e18);
        assertEq(cDAI.balanceOf(user1), 100e18);
        assertEq(balanceBeforeBorrow + 25e18, user1.balance);
    }

    function testRepayBorrowBehalf() public {
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
        Comptroller(unitroller)._supportMarket(CToken(address(cDAI)));
        hevm.prank(admin);
        Comptroller(unitroller)._supportMarket(CToken(address(cETH)));
        // set collateral factor
        hevm.prank(admin);
        Comptroller(unitroller)._setCollateralFactor(CToken(address(cDAI)), 5e17);
        hevm.prank(admin);
        Comptroller(unitroller)._setCollateralFactor(CToken(address(cETH)), 5e17);

        // user1 enter markets
        hevm.prank(user1);
        address[] memory markets = new address[](2);
        markets[0] = address(cDAI);
        markets[1] = address(cETH);
        ComptrollerInterface(unitroller).enterMarkets(markets);

        // user1 approve
        hevm.prank(user1);
        IERC20(dai).approve(address(cDAI), 100e18);

        // user1 mint
        hevm.prank(user1);
        assertTrue(cDAI.mint(100e18));
        assertEq(cDAI.balanceOf(user1), 100e18);

        // user2 enter markets
        hevm.prank(user2);
        ComptrollerInterface(unitroller).enterMarkets(markets);

        // user2 mint
        hevm.prank(user2);
        cETH.mint{ value: 100e18 }();
        assertEq(cETH.balanceOf(user2), 100e18);

        // user2 borrow
        uint256 balanceBeforeBorrowUser2 = IERC20(dai).balanceOf(user2);
        hevm.prank(user2);
        cDAI.borrow(100e18);
        assertEq(cETH.balanceOf(user2), 100e18);
        assertEq(balanceBeforeBorrowUser2 + 100e18, IERC20(dai).balanceOf(user2));

        // user1 borrow
        uint256 balanceBeforeBorrowUser1 = user1.balance;
        hevm.prank(user1);
        cETH.borrow(25e18);
        assertEq(cDAI.balanceOf(user1), 100e18);
        assertEq(balanceBeforeBorrowUser1 + 25e18, user1.balance);

        // user2 approve
        hevm.prank(user2);
        IERC20(dai).approve(address(cDAI), 100e18);

        // user2 repay
        hevm.prank(user2);
        cDAI.repayBorrowBehalf(user2, 100e18);
        assertEq(balanceBeforeBorrowUser2, IERC20(dai).balanceOf(user2));

        // user1 repay
        hevm.prank(user1);
        cETH.repayBorrowBehalf{ value: 25e18 }(user1);
        assertEq(balanceBeforeBorrowUser1, user1.balance);
    }

    function testLiquidateBorrow() public {
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
        Comptroller(unitroller)._supportMarket(CToken(address(cDAI)));
        hevm.prank(admin);
        Comptroller(unitroller)._supportMarket(CToken(address(cETH)));
        // set collateral factor
        hevm.prank(admin);
        Comptroller(unitroller)._setCollateralFactor(CToken(address(cDAI)), 5e17);
        hevm.prank(admin);
        Comptroller(unitroller)._setCollateralFactor(CToken(address(cETH)), 5e17);

        // user1 enter markets
        hevm.prank(user1);
        address[] memory markets = new address[](2);
        markets[0] = address(cDAI);
        markets[1] = address(cETH);
        ComptrollerInterface(unitroller).enterMarkets(markets);

        // user1 approve
        hevm.prank(user1);
        IERC20(dai).approve(address(cDAI), 100e18);

        // user1 mint
        hevm.prank(user1);
        assertTrue(cDAI.mint(100e18));
        assertEq(cDAI.balanceOf(user1), 100e18);

        // user2 enter markets
        hevm.prank(user2);
        ComptrollerInterface(unitroller).enterMarkets(markets);

        // user2 mint
        hevm.prank(user2);
        cETH.mint{ value: 100e18 }();
        assertEq(cETH.balanceOf(user2), 100e18);

        // user2 borrow
        uint256 balanceBeforeBorrowUser2 = IERC20(dai).balanceOf(user2);
        hevm.prank(user2);
        cDAI.borrow(100e18);
        assertEq(cETH.balanceOf(user2), 100e18);
        assertEq(balanceBeforeBorrowUser2 + 100e18, IERC20(dai).balanceOf(user2));

        // user1 borrow
        uint256 balanceBeforeBorrowUser1 = user1.balance;
        hevm.prank(user1);
        cETH.borrow(25e18);
        assertEq(cDAI.balanceOf(user1), 100e18);
        assertEq(balanceBeforeBorrowUser1 + 25e18, user1.balance);

        // set collateral factor
        hevm.prank(admin);
        Comptroller(unitroller)._setCollateralFactor(CToken(address(cDAI)), 4e17);
        hevm.prank(admin);
        Comptroller(unitroller)._setCollateralFactor(CToken(address(cETH)), 4e17);

        // liquidator approve
        hevm.prank(liquidator);
        IERC20(dai).approve(address(cDAI), 100e18);

        // liquidator liquidateBorrow user2
        hevm.prank(liquidator);
        cDAI.liquidateBorrow(user2, 24e18, CTokenInterface(cETH));

        assertEq(cETH.balanceOf(liquidator), 5832000000000000000);

        // liquidator liquidateBorrow user1
        hevm.prank(liquidator);
        cETH.liquidateBorrow{ value: 6e18 }(user1, CToken(cDAI));

        assertEq(cDAI.balanceOf(liquidator), 5832000000000000000);
    }
}
