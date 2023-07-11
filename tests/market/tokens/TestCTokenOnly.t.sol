// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "tests/market/TestBaseMarket.sol";

contract TestCToken is TestBaseMarket {
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
    }

    function testInitialize() public {
        _deployCDAI();
    }

    function testMint() public {
        _deployCDAI();

        _setupCDAIMarket();

        _enterCDAIMarket(user);

        // approve
        dai.approve(address(cDAI), 100e18);

        // mint
        assertTrue(cDAI.mint(100e18));
        assertGt(cDAI.balanceOf(user), 0);
    }

    function testRedeem() public {
        _deployCDAI();

        _setupCDAIMarket();

        _enterCDAIMarket(user);

        // approve
        dai.approve(address(cDAI), 100e18);

        uint256 balanceBeforeMint = dai.balanceOf(user);
        // mint
        assertTrue(cDAI.mint(100e18));
        assertEq(cDAI.balanceOf(user), 100e18);
        assertGt(balanceBeforeMint, dai.balanceOf(user));

        // redeem
        cDAI.redeem(cDAI.balanceOf(user));
        assertEq(cDAI.balanceOf(user), 0);
        assertEq(balanceBeforeMint, dai.balanceOf(user));
    }

    function testRedeemUnderlying() public {
        _deployCDAI();

        _setupCDAIMarket();

        _enterCDAIMarket(user);

        // approve
        dai.approve(address(cDAI), 100e18);

        uint256 balanceBeforeMint = dai.balanceOf(user);
        // mint
        assertTrue(cDAI.mint(100e18));
        assertEq(cDAI.balanceOf(user), 100e18);
        assertGt(balanceBeforeMint, dai.balanceOf(user));

        // redeem
        cDAI.redeemUnderlying(100e18);
        assertEq(cDAI.balanceOf(user), 0);
        assertEq(balanceBeforeMint, dai.balanceOf(user));
    }

    function testBorrow() public {
        _deployCDAI();

        _setupCDAIMarket();

        _enterCDAIMarket(user);

        // approve
        dai.approve(address(cDAI), 100e18);

        // mint
        assertTrue(cDAI.mint(100e18));
        assertEq(cDAI.balanceOf(user), 100e18);

        uint256 balanceBeforeBorrow = dai.balanceOf(user);
        // borrow
        cDAI.borrow(50e18);
        assertEq(cDAI.balanceOf(user), 100e18);
        assertEq(balanceBeforeBorrow + 50e18, dai.balanceOf(user));
    }

    function testRepayBorrow() public {
        _deployCDAI();

        _setupCDAIMarket();

        _enterCDAIMarket(user);

        // approve
        dai.approve(address(cDAI), 100e18);

        // mint
        assertTrue(cDAI.mint(100e18));
        assertEq(cDAI.balanceOf(user), 100e18);

        uint256 balanceBeforeBorrow = dai.balanceOf(user);
        // borrow
        cDAI.borrow(50e18);
        assertEq(cDAI.balanceOf(user), 100e18);
        assertEq(balanceBeforeBorrow + 50e18, dai.balanceOf(user));

        // approve
        dai.approve(address(cDAI), 50e18);

        // repay
        cDAI.repayBorrow(50e18);
        assertEq(balanceBeforeBorrow, dai.balanceOf(user));
    }

    function testRepayBorrowBehalf() public {
        _deployCDAI();

        _setupCDAIMarket();

        _enterCDAIMarket(user);

        // approve
        dai.approve(address(cDAI), 100e18);

        // mint
        assertTrue(cDAI.mint(100e18));
        assertEq(cDAI.balanceOf(user), 100e18);

        uint256 balanceBeforeBorrow = dai.balanceOf(user);
        // borrow
        cDAI.borrow(50e18);
        assertEq(cDAI.balanceOf(user), 100e18);
        assertEq(balanceBeforeBorrow + 50e18, dai.balanceOf(user));

        // approve
        dai.approve(address(cDAI), 50e18);

        // repay
        cDAI.repayBorrowBehalf(user, 50e18);
        assertEq(balanceBeforeBorrow, dai.balanceOf(user));
    }

    function testLiquidateBorrow() public {
        _deployCDAI();

        // support market
        vm.prank(admin);
        Lendtroller(lendtroller)._supportMarket(CToken(address(cDAI)));
        // set collateral factor
        vm.prank(admin);
        Lendtroller(lendtroller)._setCollateralFactor(
            CToken(address(cDAI)),
            6e17
        );

        // enter markets
        vm.prank(user);
        address[] memory markets = new address[](1);
        markets[0] = address(cDAI);
        LendtrollerInterface(lendtroller).enterMarkets(markets);

        // approve
        dai.approve(address(cDAI), 100e18);

        // mint
        assertTrue(cDAI.mint(100e18));
        assertEq(cDAI.balanceOf(user), 100e18);

        // borrow
        cDAI.borrow(60e18);
        assertEq(cDAI.balanceOf(user), 100e18);

        // set collateral factor
        vm.prank(admin);
        Lendtroller(lendtroller)._setCollateralFactor(
            CToken(address(cDAI)),
            5e17
        );

        // approve
        vm.prank(liquidator);
        dai.approve(address(cDAI), 100e18);

        // liquidateBorrow
        vm.prank(liquidator);
        cDAI.liquidateBorrow(user, 12e18, ICToken(cDAI));

        assertEq(cDAI.balanceOf(liquidator), 5832000000000000000);
    }
}
