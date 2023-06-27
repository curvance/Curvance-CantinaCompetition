// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
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

        // support market
        vm.prank(admin);
        Lendtroller(unitroller)._supportMarket(CToken(address(cETH)));
        // set collateral factor
        vm.prank(admin);
        Lendtroller(unitroller)._setCollateralFactor(CToken(address(cETH)), 5e17);

        // enter markets
        vm.prank(user);
        address[] memory markets = new address[](1);
        markets[0] = address(cETH);
        LendtrollerInterface(unitroller).enterMarkets(markets);

        // set borrow cap to 49
        vm.prank(admin);
        Lendtroller(unitroller)._setBorrowCapGuardian(admin);
        vm.prank(admin);
        CToken[] memory cTokens = new CToken[](1);
        cTokens[0] = CToken(address(cETH));
        uint256[] memory borrowCapAmounts = new uint256[](1);
        borrowCapAmounts[0] = 49e18;
        Lendtroller(unitroller)._setMarketBorrowCaps(cTokens, borrowCapAmounts);

        // mint
        cETH.mint{ value: 100e18 }();
        assertEq(cETH.balanceOf(user), 100e18);

        // can't borrow 50
        vm.expectRevert(LendtrollerInterface.BorrowCapReached.selector); // Update: we now revert
        cETH.borrow(50e18);

        // increase borrow cap to 51
        vm.prank(admin);
        borrowCapAmounts[0] = 51e18;
        Lendtroller(unitroller)._setMarketBorrowCaps(cTokens, borrowCapAmounts);

        uint256 balanceBeforeBorrow = user.balance;
        // borrow
        cETH.borrow(50e18);
        assertEq(cETH.balanceOf(user), 100e18);
        assertEq(balanceBeforeBorrow + 50e18, user.balance);
    }
}
