// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "tests/market/TestBaseMarket.sol";

contract TestCEtherAndCTokenIntegration is TestBaseMarket {
    receive() external payable {}

    fallback() external payable {}

    function setUp() public override {
        super.setUp();

        // prepare 200K DAI
        vm.store(
            DAI_ADDRESS,
            keccak256(abi.encodePacked(uint256(uint160(user)), uint256(2))),
            bytes32(uint256(200000e18))
        );
        vm.store(
            DAI_ADDRESS,
            keccak256(
                abi.encodePacked(uint256(uint160(liquidator)), uint256(2))
            ),
            bytes32(uint256(200000e18))
        );

        // prepare 100 ETH
        vm.deal(user, 100e18);
        vm.deal(liquidator, 100e18);
    }

    function testInitialize() public {
        _deployCDAI();
        _deployCEther();
    }

    function testMint() public {
        _deployCDAI();
        _deployCEther();

        _setupCDAIMarket();
        _setupCEtherMarket();

        _enterMarkets(user);

        // mint cDAI
        dai.approve(address(cDAI), 100e18);
        assertTrue(cDAI.mint(100e18));
        assertGt(cDAI.balanceOf(user), 0);

        // mint cETH
        cETH.mint{ value: 10e18 }();
        assertGt(cETH.balanceOf(user), 0);
    }

    function testRedeem() public {
        _deployCDAI();
        _deployCEther();

        _setupCDAIMarket();
        _setupCEtherMarket();

        _enterMarkets(user);

        uint256 daiBalanceBeforeMint = dai.balanceOf(user);
        uint256 ethBalanceBeforeMint = user.balance;

        // mint cDAI
        dai.approve(address(cDAI), 100e18);
        assertTrue(cDAI.mint(100e18));

        // mint cETH
        cETH.mint{ value: 10e18 }();

        // redeem DAI
        cDAI.redeem(cDAI.balanceOf(user));
        assertEq(cDAI.balanceOf(user), 0);
        assertEq(daiBalanceBeforeMint, dai.balanceOf(user));

        // redeem ETH
        cETH.redeem(cETH.balanceOf(user));
        assertEq(cETH.balanceOf(user), 0);
        assertEq(ethBalanceBeforeMint, user.balance);
    }

    function testRedeemUnderlying() public {
        _deployCDAI();
        _deployCEther();

        _setupCDAIMarket();
        _setupCEtherMarket();

        _enterMarkets(user);

        uint256 daiBalanceBeforeMint = dai.balanceOf(user);
        uint256 ethBalanceBeforeMint = user.balance;

        // mint cDAI
        dai.approve(address(cDAI), 100e18);
        assertTrue(cDAI.mint(100e18));

        // mint cETH
        cETH.mint{ value: 10e18 }();

        // redeem
        cDAI.redeemUnderlying(100e18);
        assertEq(cDAI.balanceOf(user), 0);
        assertEq(daiBalanceBeforeMint, dai.balanceOf(user));

        // redeem
        cETH.redeemUnderlying(10e18);
        assertEq(cETH.balanceOf(user), 0);
        assertEq(ethBalanceBeforeMint, user.balance);
    }

    function testBorrow() public {
        _deployCDAI();
        _deployCEther();

        _setupCDAIMarket();
        _setupCEtherMarket();

        _enterMarkets(user);

        // mint cDAI
        dai.approve(address(cDAI), 100e18);
        assertTrue(cDAI.mint(100e18));

        // mint cETH
        cETH.mint{ value: 10e18 }();

        uint256 daiBalanceBeforeBorrow = dai.balanceOf(user);
        uint256 ethBalanceBeforeBorrow = user.balance;

        // borrow DAI
        cDAI.borrow(50e18);
        assertEq(cDAI.balanceOf(user), 100e18);
        assertEq(daiBalanceBeforeBorrow + 50e18, dai.balanceOf(user));

        // borrow ETH
        cETH.borrow(5e18);
        assertEq(cETH.balanceOf(user), 10e18);
        assertEq(ethBalanceBeforeBorrow + 5e18, user.balance);
    }

    function testRepayBorrow() public {
        _deployCDAI();
        _deployCEther();

        _setupCDAIMarket();
        _setupCEtherMarket();

        _enterMarkets(user);

        // mint cDAI
        dai.approve(address(cDAI), 100e18);
        assertTrue(cDAI.mint(100e18));

        // mint cETH
        cETH.mint{ value: 10e18 }();

        uint256 daiBalanceBeforeBorrow = dai.balanceOf(user);
        uint256 ethBalanceBeforeBorrow = user.balance;

        // borrow DAI
        cDAI.borrow(50e18);
        assertEq(cDAI.balanceOf(user), 100e18);
        assertEq(daiBalanceBeforeBorrow + 50e18, dai.balanceOf(user));

        // borrow ETH
        cETH.borrow(5e18);
        assertEq(cETH.balanceOf(user), 10e18);
        assertEq(ethBalanceBeforeBorrow + 5e18, user.balance);

        // repay DAI
        dai.approve(address(cDAI), 50e18);
        cDAI.repayBorrow(50e18);
        assertEq(daiBalanceBeforeBorrow, dai.balanceOf(user));

        // repay ETH
        cETH.repayBorrow{ value: 5e18 }();
        assertEq(ethBalanceBeforeBorrow, user.balance);
    }

    function testRepayBorrowBehalf() public {
        _deployCDAI();
        _deployCEther();

        _setupCDAIMarket();
        _setupCEtherMarket();

        _enterMarkets(user);

        // mint cDAI
        dai.approve(address(cDAI), 100e18);
        assertTrue(cDAI.mint(100e18));

        // mint cETH
        cETH.mint{ value: 10e18 }();

        uint256 daiBalanceBeforeBorrow = dai.balanceOf(user);
        uint256 ethBalanceBeforeBorrow = user.balance;

        // borrow DAI
        cDAI.borrow(50e18);
        assertEq(cDAI.balanceOf(user), 100e18);
        assertEq(daiBalanceBeforeBorrow + 50e18, dai.balanceOf(user));

        // borrow ETH
        cETH.borrow(5e18);
        assertEq(cETH.balanceOf(user), 10e18);
        assertEq(ethBalanceBeforeBorrow + 5e18, user.balance);

        // repay DAI
        dai.approve(address(cDAI), 50e18);
        cDAI.repayBorrowBehalf(user, 50e18);
        assertEq(daiBalanceBeforeBorrow, dai.balanceOf(user));

        // repay ETH
        cETH.repayBorrowBehalf{ value: 5e18 }(user);
        assertEq(ethBalanceBeforeBorrow, user.balance);
    }

    function testLiquidateBorrow() public {
        _deployCDAI();
        _deployCEther();

        _setupCDAIMarket();
        _setupCEtherMarket();

        _enterMarkets(user);

        // mint cDAI
        dai.approve(address(cDAI), 100e18);
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
        Lendtroller(lendtroller)._setCollateralFactor(
            CToken(address(cDAI)),
            4e17
        );
        vm.prank(admin);
        Lendtroller(lendtroller)._setCollateralFactor(
            CToken(address(cETH)),
            4e17
        );

        // liquidateBorrow DAI
        vm.prank(liquidator);
        dai.approve(address(cDAI), 100e18);
        vm.prank(liquidator);
        cDAI.liquidateBorrow(user, 12e18, ICToken(cDAI));
        assertEq(cDAI.balanceOf(liquidator), 5832000000000000000);

        // liquidateBorrow ETH
        vm.prank(liquidator);
        cETH.liquidateBorrow{ value: 12e17 }(user, CToken(cETH));

        assertEq(cETH.balanceOf(liquidator), 583200000000000000);
    }
}
