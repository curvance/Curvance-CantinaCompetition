// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseOracleRouter } from "../TestBaseOracleRouter.sol";
import { IChainlink } from "contracts/interfaces/external/chainlink/IChainlink.sol";
import { IMToken, AccountSnapshot } from "contracts/interfaces/market/IMToken.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { OracleRouter } from "contracts/oracles/OracleRouter.sol";

contract GetPricesForMarket is TestBaseOracleRouter {
    IMToken[] public assets;

    function setUp() public override {
        super.setUp();

        assets.push(IMToken(address(mUSDC)));
    }

    function test_getPricesForMarket_fail_whenAssetsLengthIsZero() public {
        assets.pop();

        vm.expectRevert(OracleRouter.OracleRouter__InvalidParameter.selector);
        oracleRouter.getPricesForMarket(address(this), assets, 1);
    }

    function test_getPricesForMarket_fail_whenMarketNotStarted() public {
        vm.expectRevert();
        oracleRouter.getPricesForMarket(address(this), assets, 1);
    }

    function test_getPricesForMarket_fail_whenNoFeedsAvailable() public {
        deal(_USDC_ADDRESS, address(this), 1e18);
        vm.prank(address(this));
        IERC20(_USDC_ADDRESS).approve(address(mUSDC), 1e18);
        vm.prank(address(marketManager));
        mUSDC.startMarket(address(this));

        vm.expectRevert(OracleRouter.OracleRouter__NotSupported.selector);
        oracleRouter.getPricesForMarket(address(this), assets, 1);
    }

    function test_getPricesForMarket_fail_whenErrorCodeExceedsBreakpoint()
        public
    {
        deal(_USDC_ADDRESS, address(this), 1e18);
        vm.prank(address(this));
        IERC20(_USDC_ADDRESS).approve(address(mUSDC), 1e18);
        vm.prank(address(marketManager));
        mUSDC.startMarket(address(this));

        _addSinglePriceFeed();

        vm.expectRevert(OracleRouter.OracleRouter__ErrorCodeFlagged.selector);
        oracleRouter.getPricesForMarket(address(this), assets, 0);
    }

    function test_getPricesForMarket_success() public {
        deal(_USDC_ADDRESS, address(this), 1e18);
        vm.prank(address(this));
        IERC20(_USDC_ADDRESS).approve(address(mUSDC), 1e18);
        vm.prank(address(marketManager));
        mUSDC.startMarket(address(this));

        _addSinglePriceFeed();

        (
            AccountSnapshot[] memory snapshots,
            uint256[] memory underlyingPrices,
            uint256 numAssets
        ) = oracleRouter.getPricesForMarket(address(this), assets, 1);

        (, int256 usdcPrice, , , ) = IChainlink(_CHAINLINK_USDC_USD)
            .latestRoundData();

        assertEq(numAssets, 1);

        for (uint256 i = 0; i < numAssets; i++) {
            assertEq(underlyingPrices[i], uint256(usdcPrice) * 1e10);
            assertEq(snapshots[i].asset, address(mUSDC));
            assertFalse(snapshots[i].isCToken);
            assertEq(snapshots[i].decimals, IERC20(_USDC_ADDRESS).decimals());
            assertEq(
                assets[i].balanceOf(address(this)),
                mUSDC.balanceOf(address(this))
            );
            assertEq(snapshots[i].debtBalance, 0);
            assertEq(snapshots[i].exchangeRate, 0);
        }
    }
}
