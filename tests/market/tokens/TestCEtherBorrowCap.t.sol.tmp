// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "tests/market/TestBaseMarket.sol";

contract TestCEtherBorrowCap is TestBaseMarket {
    receive() external payable {}

    fallback() external payable {}

    function setUp() public override {
        super.setUp();

        // prepare 200K ETH
        vm.deal(user, 200000e18);
        vm.deal(liquidator, 200000e18);
    }

    function testBorrowCap() public {
        _deployCEther();

        _setupCEtherMarket();

        _enterCEtherMarket(user);

        // set borrow cap to 49
        vm.prank(admin);
        Lendtroller(lendtroller)._setBorrowCapGuardian(admin);
        vm.prank(admin);
        CToken[] memory cTokens = new CToken[](1);
        cTokens[0] = CToken(address(cETH));
        uint256[] memory borrowCapAmounts = new uint256[](1);
        borrowCapAmounts[0] = 49e18;
        Lendtroller(lendtroller)._setMarketBorrowCaps(
            cTokens,
            borrowCapAmounts
        );

        // mint
        cETH.mint{ value: 100e18 }();
        assertEq(cETH.balanceOf(user), 100e18);

        // can't borrow 50
        vm.expectRevert(ILendtroller.BorrowCapReached.selector); // Update: we now revert
        cETH.borrow(50e18);

        // increase borrow cap to 51
        vm.prank(admin);
        borrowCapAmounts[0] = 51e18;
        Lendtroller(lendtroller)._setMarketBorrowCaps(
            cTokens,
            borrowCapAmounts
        );

        uint256 balanceBeforeBorrow = user.balance;
        // borrow
        cETH.borrow(50e18);
        assertEq(cETH.balanceOf(user), 100e18);
        assertEq(balanceBeforeBorrow + 50e18, user.balance);
    }
}
