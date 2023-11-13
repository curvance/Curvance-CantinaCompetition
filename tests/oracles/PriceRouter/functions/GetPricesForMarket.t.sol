// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBasePriceRouter } from "../TestBasePriceRouter.sol";
import { IChainlink } from "contracts/interfaces/external/chainlink/IChainlink.sol";
import { IMToken, AccountSnapshot } from "contracts/interfaces/market/IMToken.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { PriceRouter } from "contracts/oracles/PriceRouter.sol";

contract GetPricesForMarket is TestBasePriceRouter {
    IMToken[] public assets;

    function setUp() public override {
        super.setUp();

        assets.push(IMToken(address(mUSDC)));
    }

    function test_getPricesForMarket_fail_whenAssetsLengthIsZero() public {
        assets.pop();

        vm.expectRevert(PriceRouter.PriceRouter__InvalidParameter.selector);
        priceRouter.getPricesForMarket(address(this), assets, 1);
    }

    function test_getPricesForMarket_fail_whenMarketNotStarted() public {
        vm.expectRevert();
        priceRouter.getPricesForMarket(address(this), assets, 1);
    }

    function test_getPricesForMarket_fail_whenNoFeedsAvailable() public {
        deal(_USDC_ADDRESS, address(this), 1e18);
        vm.prank(address(this));
        IERC20(_USDC_ADDRESS).approve(address(mUSDC), 1e18);
        vm.prank(address(lendtroller));
        mUSDC.startMarket(address(this));

        vm.expectRevert(PriceRouter.PriceRouter__NotSupported.selector);
        priceRouter.getPricesForMarket(address(this), assets, 1);
    }

    function test_getPricesForMarket_fail_whenErrorCodeExceedsBreakpoint()
        public
    {
        deal(_USDC_ADDRESS, address(this), 1e18);
        vm.prank(address(this));
        IERC20(_USDC_ADDRESS).approve(address(mUSDC), 1e18);
        vm.prank(address(lendtroller));
        mUSDC.startMarket(address(this));

        _addSinglePriceFeed();

        vm.expectRevert(PriceRouter.PriceRouter__ErrorCodeFlagged.selector);
        priceRouter.getPricesForMarket(address(this), assets, 0);
    }

    function test_getPricesForMarket_success() public {
        deal(_USDC_ADDRESS, address(this), 1e18);
        vm.prank(address(this));
        IERC20(_USDC_ADDRESS).approve(address(mUSDC), 1e18);
        vm.prank(address(lendtroller));
        mUSDC.startMarket(address(this));

        _addSinglePriceFeed();

        (
            AccountSnapshot[] memory snapshots,
            uint256[] memory underlyingPrices,
            uint256 numAssets
        ) = priceRouter.getPricesForMarket(address(this), assets, 1);

        (, int256 usdcPrice, , , ) = IChainlink(_CHAINLINK_USDC_USD)
            .latestRoundData();

        assertEq(numAssets, 1);

        for (uint256 i = 0; i < numAssets; i++) {
            assertEq(underlyingPrices[i], uint256(usdcPrice) * 1e10);
            assertEq(snapshots[i].asset, address(mUSDC));
            assertFalse(snapshots[i].isCToken);
            assertEq(snapshots[i].decimals, IERC20(_USDC_ADDRESS).decimals());
            // assertEq(snapshots[i].balance, mUSDC.balanceOf(address(this)));
            assertEq(snapshots[i].debtBalance, 0);
            assertEq(snapshots[i].exchangeRate, 1e18);
        }
    }
}
