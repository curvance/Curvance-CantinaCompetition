// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseLendtroller } from "../TestBaseLendtroller.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";
import { IMToken, AccountSnapshot } from "contracts/interfaces/market/IMToken.sol";

contract CanBorrowWithNotifyTest is TestBaseLendtroller {
    event MarketEntered(address mToken, address account);

    function setUp() public override {
        super.setUp();

        lendtroller.listToken(address(dUSDC));
    }

    function test_canBorrowWithNotify_fail_whenCallerIsNotMToken() public {
        vm.expectRevert(Lendtroller.Lendtroller__Unauthorized.selector);
        lendtroller.canBorrowWithNotify(address(dUSDC), user1, 100e6);
    }

    function test_canBorrowWithNotify_fail_whenCallerMTokenIsNotListed()
        public
    {
        vm.prank(address(dDAI));

        vm.expectRevert(Lendtroller.Lendtroller__TokenNotListed.selector);
        lendtroller.canBorrowWithNotify(address(dDAI), user1, 100e6);
    }

    function test_canBorrowWithNotify_fail_whenBorrowPaused() public {
        lendtroller.setBorrowPaused(address(dUSDC), true);

        vm.prank(address(dUSDC));

        vm.expectRevert(Lendtroller.Lendtroller__Paused.selector);
        lendtroller.canBorrowWithNotify(address(dUSDC), user1, 100e6);
    }

    function test_canBorrowWithNotify_fail_whenMTokenIsNotListed() public {
        vm.prank(address(dUSDC));

        vm.expectRevert(Lendtroller.Lendtroller__Unauthorized.selector);
        lendtroller.canBorrowWithNotify(address(dDAI), user1, 100e6);
    }

    function test_canBorrowWithNotify_fail_whenCallerIsNotMTokenAndBorrowerNotInMarket()
        public
    {
        lendtroller.listToken(address(dDAI));

        vm.prank(address(dUSDC));

        vm.expectRevert(Lendtroller.Lendtroller__Unauthorized.selector);
        lendtroller.canBorrowWithNotify(address(dDAI), user1, 100e6);
    }

    // function test_canBorrowWithNotify_fail_whenExceedsBorrowCap() external {
    //     skip(gaugePool.startTime() - block.timestamp);
    //     chainlinkUsdcUsd.updateRoundData(0, 1e8, block.timestamp, block.timestamp);
    //     chainlinkUsdcEth.updateRoundData(0, 1e18, block.timestamp, block.timestamp);

    //     IMToken[] memory mTokens = new IMToken[](1);
    //     uint256[] memory borrowCaps = new uint256[](1);
    //     mTokens[0] = IMToken(address(cBALRETH));
    //     borrowCaps[0] = 100e6 - 1;

    //     lendtroller.listToken(address(cBALRETH));
    //     lendtroller.setCTokenCollateralCaps(mTokens, borrowCaps);

    //     vm.expectRevert(Lendtroller.Lendtroller__BorrowCapReached.selector);
    //     vm.prank(address(cBALRETH));
    //     lendtroller.canBorrowWithNotify(address(cBALRETH), user1, 100e6);
    // }

    // function test_canBorrowWithNotify_success_whenCapNotExceeded() external {
    //     skip(gaugePool.startTime() - block.timestamp);
    //     chainlinkUsdcUsd.updateRoundData(0, 1e8, block.timestamp, block.timestamp);
    //     chainlinkUsdcEth.updateRoundData(0, 1e18, block.timestamp, block.timestamp);

    //     IMToken[] memory mTokens = new IMToken[](1);
    //     uint256[] memory borrowCaps = new uint256[](1);
    //     mTokens[0] = IMToken(address(cBALRETH));
    //     borrowCaps[0] = 100e6;

    //     lendtroller.listToken(address(cBALRETH));
    //     lendtroller.setCTokenCollateralCaps(mTokens, borrowCaps);

    //     vm.prank(address(cBALRETH));
    //     lendtroller.canBorrowWithNotify(address(cBALRETH), user1, borrowCaps[0] - 1);
    // }

    function test_canBorrowWithNotify_fail_whenInsufficientLiquidity() public {
        skip(gaugePool.startTime() - block.timestamp);
        chainlinkUsdcUsd.updateRoundData(
            0,
            1e8,
            block.timestamp,
            block.timestamp
        );
        chainlinkUsdcEth.updateRoundData(
            0,
            1e18,
            block.timestamp,
            block.timestamp
        );

        vm.expectRevert(
            Lendtroller.Lendtroller__InsufficientLiquidity.selector
        );
        vm.prank(address(dUSDC));
        lendtroller.canBorrowWithNotify(address(dUSDC), user1, 100e6);
    }

    function test_canBorrowWithNotify_success_whenSufficientLiquidity()
        public
    {
        skip(gaugePool.startTime() - block.timestamp);
        chainlinkEthUsd.updateRoundData(
            0,
            1500e8,
            block.timestamp,
            block.timestamp
        );
        chainlinkUsdcUsd.updateRoundData(
            0,
            1e8,
            block.timestamp,
            block.timestamp
        );
        chainlinkUsdcEth.updateRoundData(
            0,
            1500e18,
            block.timestamp,
            block.timestamp
        );

        lendtroller.listToken(address(cBALRETH));
        lendtroller.updateCollateralToken(
            IMToken(address(cBALRETH)),
            7000,
            3000,
            3000,
            2000,
            2000,
            100,
            1000
        );

        address[] memory tokens = new address[](1);
        tokens[0] = address(cBALRETH);
        uint256[] memory caps = new uint256[](1);
        caps[0] = 100_000e18;
        lendtroller.setCTokenCollateralCaps(tokens, caps);

        // Need some CTokens/collateral to have enough liquidity for borrowing
        deal(address(balRETH), user1, 10_000e18);
        vm.startPrank(user1);
        balRETH.approve(address(cBALRETH), 1_000e18);
        cBALRETH.mint(1_000e18);
        lendtroller.postCollateral(user1, address(cBALRETH), 999e18);
        vm.stopPrank();

        vm.prank(address(dUSDC));
        lendtroller.canBorrowWithNotify(address(dUSDC), user1, 100e6);
        uint256 cooldownTimestamp = lendtroller.accountAssets(user1);
        assertEq(cooldownTimestamp, block.timestamp);

        AccountSnapshot memory snapshot = cBALRETH.getSnapshotPacked(user1);
        (uint256 price, ) = priceRouter.getPrice(
            cBALRETH.underlying(),
            true,
            true
        );
        (, uint256 collRatio, , , , , , , ) = lendtroller.tokenData(
            address(cBALRETH)
        );
        uint256 assetValue = (price *
            ((999e18 * snapshot.exchangeRate) / 1e18)) /
            10 ** cBALRETH.decimals();
        uint256 maxBorrow = (assetValue * collRatio) / 1e18;

        // max amount of USDC that can be borrowed based on provided collateral in cBALRETH
        uint256 borrowInUSDC = (maxBorrow / 10 ** cBALRETH.decimals()) *
            10 ** dUSDC.decimals();
        vm.prank(address(dUSDC));
        lendtroller.canBorrowWithNotify(address(dUSDC), user1, borrowInUSDC);
        cooldownTimestamp = lendtroller.accountAssets(user1);
        assertEq(cooldownTimestamp, block.timestamp);

        // should fail when borrowing more than is allowed by provided collateral
        vm.expectRevert(
            Lendtroller.Lendtroller__InsufficientLiquidity.selector
        );
        vm.prank(address(dUSDC));
        lendtroller.canBorrowWithNotify(
            address(dUSDC),
            user1,
            borrowInUSDC + 1e6
        );
    }

    function test_canBorrowWithNotify_success_entersUserInMarket() external {
        skip(gaugePool.startTime() - block.timestamp);
        chainlinkUsdcUsd.updateRoundData(
            0,
            1e8,
            block.timestamp,
            block.timestamp
        );
        chainlinkUsdcEth.updateRoundData(
            0,
            1e18,
            block.timestamp,
            block.timestamp
        );

        assertFalse(lendtroller.hasPosition(address(dUSDC), user1));
        IMToken[] memory accountAssets = lendtroller.getAccountAssets(user1);
        assertEq(accountAssets.length, 0);

        vm.prank(address(dUSDC));
        lendtroller.canBorrowWithNotify(address(dUSDC), user1, 0);

        assertTrue(lendtroller.hasPosition(address(dUSDC), user1));

        accountAssets = lendtroller.getAccountAssets(user1);
        assertEq(accountAssets.length, 1);
        assertEq(address(accountAssets[0]), address(dUSDC));
    }
}
