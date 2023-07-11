// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "tests/market/TestBaseMarket.sol";

contract TestCTokenBorrowCap is TestBaseMarket {
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

    function testBorrowCap() public {
        _deployCDAI();

        _setupCDAIMarket();

        _enterCDAIMarket(user);

        // set borrow cap to 49
        vm.prank(admin);
        Lendtroller(lendtroller)._setBorrowCapGuardian(admin);
        vm.prank(admin);
        CToken[] memory cTokens = new CToken[](1);
        cTokens[0] = cDAI;
        uint256[] memory borrowCapAmounts = new uint256[](1);
        borrowCapAmounts[0] = 49e18;
        Lendtroller(lendtroller)._setMarketBorrowCaps(
            cTokens,
            borrowCapAmounts
        );

        // approve
        dai.approve(address(cDAI), 100e18);

        // mint
        assertTrue(cDAI.mint(100e18));
        assertEq(cDAI.balanceOf(user), 100e18);

        // can't borrow 50
        vm.expectRevert(ILendtroller.BorrowCapReached.selector); // Update: we now revert
        cDAI.borrow(50e18);

        // increase borrow cap to 51
        vm.prank(admin);
        borrowCapAmounts[0] = 51e18;
        Lendtroller(lendtroller)._setMarketBorrowCaps(
            cTokens,
            borrowCapAmounts
        );

        uint256 balanceBeforeBorrow = dai.balanceOf(user);
        // can borrow 50
        cDAI.borrow(50e18);
        assertEq(cDAI.balanceOf(user), 100e18);
        assertEq(balanceBeforeBorrow + 50e18, dai.balanceOf(user));
    }
}
