// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseLendtroller } from "../TestBaseLendtroller.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";
import { IMToken, AccountSnapshot } from "contracts/interfaces/market/IMToken.sol";
import "hardhat/console.sol";

contract CanBorrowTest is TestBaseLendtroller {
    event MarketEntered(address mToken, address account);

    function setUp() public override {
        super.setUp();

        lendtroller.listToken(address(dUSDC));
    }

    function test_canBorrow_fail_whenBorrowPaused() public {
        lendtroller.setBorrowPaused(IMToken(address(dUSDC)), true);

        vm.prank(address(dUSDC));

        vm.expectRevert(Lendtroller.Lendtroller__Paused.selector);
        lendtroller.canBorrow(address(dUSDC), user1, 100e6);
    }

    function test_canBorrow_fail_whenMTokenIsNotListed() public {
        vm.prank(address(dUSDC));

        vm.expectRevert(Lendtroller.Lendtroller__TokenNotListed.selector);
        lendtroller.canBorrow(address(dDAI), user1, 100e6);
    }

    function test_canBorrow_fail_whenCallerIsNotMTokenAndBorrowerNotInMarket()
        public
    {
        lendtroller.listToken(address(dDAI));

        vm.prank(address(dUSDC));

        vm.expectRevert(Lendtroller.Lendtroller__AddressUnauthorized.selector);
        lendtroller.canBorrow(address(dDAI), user1, 100e6);
    }

    function test_canBorrow_fail_whenInsufficientLiquidity() public {
        skip(gaugePool.startTime() - block.timestamp);
        chainlinkUsdcUsd.updateRoundData(0, 1e8, block.timestamp, block.timestamp);
        chainlinkUsdcEth.updateRoundData(0, 1e18, block.timestamp, block.timestamp);

        address[] memory tokens = new address[](1);
        tokens[0] = address(dUSDC);

        vm.prank(user1);
        lendtroller.enterMarkets(tokens);

        vm.expectRevert(Lendtroller.Lendtroller__InsufficientLiquidity.selector);
        lendtroller.canBorrow(address(dUSDC), user1, 100e6);
    }

    function test_getHypotheticalLiquidity_returnsCorrectValues() external {
        skip(gaugePool.startTime() - block.timestamp);
        console.log("Oracles: ", address(chainlinkUsdcUsd), address(chainlinkUsdcEth));
        chainlinkUsdcUsd.updateRoundData(0, 1e8, block.timestamp, block.timestamp);
        chainlinkUsdcEth.updateRoundData(0, 1e18, block.timestamp, block.timestamp);

        address[] memory tokens = new address[](1);
        tokens[0] = address(dUSDC);

        // deal(address(dUSDC), address(this), 10e6);
        // vm.prank(address(this));
        // dUSDC.depositReserves(1e6);

        // deal(address(usdc), user1, 10_000e6);
        vm.startPrank(user1);
        // usdc.approve(address(dUSDC), type(uint256).max);
        lendtroller.enterMarkets(tokens);
        // dUSDC.mint(1000e6);
        vm.stopPrank();

        lendtroller.canBorrow(address(dUSDC), user1, 100e6);

        // (uint256 maxBorrow, uint256 newDebt) = lendtroller.getHypotheticalLiquidity(user1, address(dUSDC), 1e6, 1000e6);
        // console.log("Max Borrow: ", maxBorrow);
        // console.log("New Debt: ", newDebt);
    }

    // function test_canBorrow_fail_whenExceedsBorrowCaps() public {
    //     IMToken[] memory mTokens = new IMToken[](1);
    //     uint256[] memory borrowCaps = new uint256[](1);
    //     mTokens[0] = IMToken(address(dUSDC));
    //     borrowCaps[0] = 100e6 - 1;

    //     lendtroller.setCTokenCollateralCaps(mTokens, borrowCaps);

    //     vm.prank(address(dUSDC));

    //     vm.expectRevert(Lendtroller.Lendtroller__BorrowCapReached.selector);
    //     lendtroller.canBorrow(address(dUSDC), user1, 100e6);
    // }

    // function test_canBorrow_success() public {
    //     address[] memory tokens = new address[](1);
    //     tokens[0] = address(dUSDC);

    //     vm.prank(user1);
    //     lendtroller.enterMarkets(tokens);

    //     lendtroller.canBorrow(address(dUSDC), user1, 100e6);

    //     assertTrue(lendtroller.getAccountMembership(address(dUSDC), user1));
    // }
}
