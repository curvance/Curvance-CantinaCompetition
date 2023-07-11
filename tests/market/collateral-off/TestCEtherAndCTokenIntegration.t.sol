// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "tests/market/TestBaseMarket.sol";

contract TestCEtherAndCTokenIntegration is TestBaseMarket {
    receive() external payable {}

    fallback() external payable {}

    function setUp() public override {
        super.setUp();

        priceOracle.setDirectPrice(E_ADDRESS, 1000e18);

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

    function testUserCollateralOffAndCannotBorrow() public {
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

        CToken[] memory cTokens = new CToken[](2);
        cTokens[0] = cDAI;
        cTokens[1] = cETH;
        vm.prank(user);
        Lendtroller(lendtroller).setUserDisableCollateral(cTokens, true);

        vm.expectRevert(ILendtroller.InsufficientLiquidity.selector);
        cDAI.borrow(50e18);
    }

    function testCollateralOffAndCannotBorrow() public {
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

        CToken[] memory cTokens = new CToken[](2);
        cTokens[0] = cDAI;
        cTokens[1] = cETH;
        vm.prank(admin);
        Lendtroller(lendtroller)._setDisableCollateral(cTokens, true);

        vm.expectRevert(ILendtroller.InsufficientLiquidity.selector);
        cDAI.borrow(50e18);
    }

    function testCannotDisableCollateralWhenNotSafe() public {
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

        CToken[] memory cTokens = new CToken[](2);
        cTokens[0] = cDAI;
        cTokens[1] = cETH;
        vm.prank(user);
        vm.expectRevert(ILendtroller.InsufficientLiquidity.selector);
        Lendtroller(lendtroller).setUserDisableCollateral(cTokens, true);
    }
}
