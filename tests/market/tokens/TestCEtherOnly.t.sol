// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "tests/market/TestBaseMarket.sol";

contract TestCEther is TestBaseMarket {
    receive() external payable {}

    fallback() external payable {}

    function setUp() public override {
        super.setUp();

        // prepare 200K ETH
        vm.deal(user, 200000e18);
        vm.deal(liquidator, 200000e18);
    }

    function testInitialize() public {
        _deployCEther();
    }

    function testMint() public {
        _deployCEther();

        // support market
        vm.prank(admin);
        Lendtroller(lendtroller)._supportMarket(CToken(address(cETH)));
        // set collateral factor
        vm.prank(admin);
        Lendtroller(lendtroller)._setCollateralFactor(
            CToken(address(cETH)),
            5e17
        );

        // enter markets
        vm.prank(user);
        address[] memory markets = new address[](1);
        markets[0] = address(cETH);
        ILendtroller(lendtroller).enterMarkets(markets);

        // mint
        cETH.mint{ value: 100e18 }();
        assertGt(cETH.balanceOf(user), 0);
    }

    function testRedeem() public {
        _deployCEther();

        _setupCEtherMarket();

        _enterCEtherMarket(user);

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
        _deployCEther();

        _setupCEtherMarket();

        _enterCEtherMarket(user);

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
        _deployCEther();

        _setupCEtherMarket();

        _enterCEtherMarket(user);

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
        _deployCEther();

        _setupCEtherMarket();

        _enterCEtherMarket(user);

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
        _deployCEther();

        _setupCEtherMarket();

        _enterCEtherMarket(user);

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
        _deployCEther();

        // support market
        vm.prank(admin);
        Lendtroller(lendtroller)._supportMarket(CToken(address(cETH)));
        // set collateral factor
        vm.prank(admin);
        Lendtroller(lendtroller)._setCollateralFactor(
            CToken(address(cETH)),
            6e17
        );

        // enter markets
        vm.prank(user);
        address[] memory markets = new address[](1);
        markets[0] = address(cETH);
        ILendtroller(lendtroller).enterMarkets(markets);

        // mint
        cETH.mint{ value: 100e18 }();
        assertEq(cETH.balanceOf(user), 100e18);

        // borrow
        cETH.borrow(60e18);
        assertEq(cETH.balanceOf(user), 100e18);

        // set collateral factor
        vm.prank(admin);
        Lendtroller(lendtroller)._setCollateralFactor(
            CToken(address(cETH)),
            5e17
        );

        // liquidateBorrow
        vm.prank(liquidator);
        cETH.liquidateBorrow{ value: 12e18 }(user, CToken(cETH));

        assertEq(cETH.balanceOf(liquidator), 5832000000000000000);
    }
}
