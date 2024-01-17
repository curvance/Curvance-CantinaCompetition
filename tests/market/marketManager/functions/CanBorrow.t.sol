// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseMarketManager } from "../TestBaseMarketManager.sol";
import { MarketManager } from "contracts/market/MarketManager.sol";
import { IMToken, AccountSnapshot } from "contracts/interfaces/market/IMToken.sol";

contract CanBorrowTest is TestBaseMarketManager {
    event MarketEntered(address mToken, address account);

    function setUp() public override {
        super.setUp();

        marketManager.listToken(address(dUSDC));
        skip(gaugePool.startTime() - block.timestamp);

        mockWethFeed.setMockUpdatedAt(block.timestamp);
        mockRethFeed.setMockUpdatedAt(block.timestamp);
    }

    function test_canBorrow_fail_whenBorrowPaused() public {
        marketManager.setBorrowPaused(address(dUSDC), true);

        vm.prank(address(dUSDC));

        vm.expectRevert(MarketManager.MarketManager__Paused.selector);
        marketManager.canBorrow(address(dUSDC), user1, 100e6);
    }

    function test_canBorrow_fail_whenMTokenIsNotListed() public {
        vm.prank(address(dUSDC));

        vm.expectRevert(MarketManager.MarketManager__TokenNotListed.selector);
        marketManager.canBorrow(address(dDAI), user1, 100e6);
    }

    function test_canBorrow_fail_whenCallerIsNotMTokenAndBorrowerNotInMarket()
        public
    {
        marketManager.listToken(address(dDAI));

        vm.prank(address(dUSDC));

        vm.expectRevert(MarketManager.MarketManager__Unauthorized.selector);
        marketManager.canBorrow(address(dDAI), user1, 100e6);
    }

    function test_canBorrow_fail_whenInsufficientLiquidity() public {
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
            MarketManager.MarketManager__InsufficientCollateral.selector
        );
        vm.prank(address(dUSDC));
        marketManager.canBorrow(address(dUSDC), user1, 100e6);
    }

    function test_canBorrow_success_whenSufficientLiquidity() public {
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

        marketManager.listToken(address(cBALRETH));
        marketManager.updateCollateralToken(
            IMToken(address(cBALRETH)),
            7000,
            4000,
            3000,
            200,
            400,
            10,
            1000
        );
        address[] memory tokens = new address[](1);
        tokens[0] = address(cBALRETH);
        uint256[] memory caps = new uint256[](1);
        caps[0] = 100_000e18;
        marketManager.setCTokenCollateralCaps(tokens, caps);

        // Need some CTokens/collateral to have enough liquidity for borrowing
        deal(address(balRETH), user1, 10_000e18);
        vm.startPrank(user1);
        balRETH.approve(address(cBALRETH), 1_000e18);
        cBALRETH.deposit(1_000e18, user1);
        marketManager.postCollateral(user1, address(cBALRETH), 999e18);
        vm.stopPrank();

        vm.prank(address(dUSDC));
        marketManager.canBorrow(address(dUSDC), user1, 100e6);

        AccountSnapshot memory snapshot = cBALRETH.getSnapshotPacked(user1);
        (uint256 price, ) = priceRouter.getPrice(cBALRETH.asset(), true, true);
        (, uint256 collRatio, , , , , , , ) = marketManager.tokenData(
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
        marketManager.canBorrow(address(dUSDC), user1, borrowInUSDC);

        // should fail when borrowing more than is allowed by provided collateral
        vm.expectRevert(
            MarketManager.MarketManager__InsufficientCollateral.selector
        );
        vm.prank(address(dUSDC));
        marketManager.canBorrow(address(dUSDC), user1, borrowInUSDC + 1e6);
    }

    function test_canBorrow_fail_entersUserInMarket() external {
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

        vm.expectRevert(MarketManager.MarketManager__Unauthorized.selector);
        marketManager.canBorrow(address(dUSDC), user1, 0);
    }

    function test_canBorrow_success_entersUserInMarket() external {
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

        assertFalse(marketManager.hasPosition(address(dUSDC), user1));
        IMToken[] memory accountAssets = marketManager.assetsOf(user1);
        assertEq(accountAssets.length, 0);

        vm.prank(address(dUSDC));
        marketManager.canBorrow(address(dUSDC), user1, 0);

        assertTrue(marketManager.hasPosition(address(dUSDC), user1));

        accountAssets = marketManager.assetsOf(user1);
        assertEq(accountAssets.length, 1);
        assertEq(address(accountAssets[0]), address(dUSDC));
    }

    // function test_canBorrow_fail_whenExceedsBorrowCap() external {
    //     chainlinkUsdcUsd.updateRoundData(
    //         0,
    //         1e8,
    //         block.timestamp,
    //         block.timestamp
    //     );
    //     chainlinkUsdcEth.updateRoundData(
    //         0,
    //         1e18,
    //         block.timestamp,
    //         block.timestamp
    //     );

    //     IMToken[] memory mTokens = new IMToken[](1);
    //     uint256[] memory borrowCaps = new uint256[](1);
    //     mTokens[0] = IMToken(address(cBALRETH));
    //     borrowCaps[0] = 100e6 - 1;

    //     marketManager.listToken(address(cBALRETH));
    //     marketManager.setCTokenCollateralCaps(mTokens, borrowCaps);

    //     vm.expectRevert(MarketManager.MarketManager__BorrowCapReached.selector);
    //     vm.prank(address(cBALRETH));
    //     marketManager.canBorrow(address(cBALRETH), user1, 100e6);
    // }

    // function test_canBorrow_success_whenCapNotExceeded() external {
    //     chainlinkUsdcUsd.updateRoundData(
    //         0,
    //         1e8,
    //         block.timestamp,
    //         block.timestamp
    //     );
    //     chainlinkUsdcEth.updateRoundData(
    //         0,
    //         1e18,
    //         block.timestamp,
    //         block.timestamp
    //     );

    //     IMToken[] memory mTokens = new IMToken[](1);
    //     uint256[] memory borrowCaps = new uint256[](1);
    //     mTokens[0] = IMToken(address(cBALRETH));
    //     borrowCaps[0] = 100e6;

    //     marketManager.listToken(address(cBALRETH));
    //     marketManager.setCTokenCollateralCaps(mTokens, borrowCaps);

    //     vm.prank(address(cBALRETH));
    //     marketManager.canBorrow(address(cBALRETH), user1, borrowCaps[0] - 1);
    // }
}
