// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import { TestBasePriceRouterV2 } from "../TestBasePriceRouterV2.sol";

contract GetPriceMultiTest is TestBasePriceRouterV2 {
    address[] public assets;
    bool[] public inUSD;
    bool[] public getLower;

    function setUp() public override {
        super.setUp();

        assets.push(_USDC_ADDRESS);
        inUSD.push(true);
        getLower.push(true);

        assets.push(_USDC_ADDRESS);
        inUSD.push(false);
        getLower.push(true);
    }

    function test_getPriceMulti_fail_whenNoFeedsAvailable() public {
        vm.expectRevert("PriceRouter: no feeds available");
        priceRouter.getPriceMulti(assets, inUSD, getLower);
    }

    function test_getPriceMulti_success() public {
        _addSinglePriceFeed();

        (, int256 usdcPrice, , , ) = AggregatorV3Interface(_CHAINLINK_USDC_USD)
            .latestRoundData();
        (, int256 ethPrice, , , ) = AggregatorV3Interface(_CHAINLINK_USDC_ETH)
            .latestRoundData();

        (uint256[] memory prices, uint256[] memory errorCodes) = priceRouter
            .getPriceMulti(assets, inUSD, getLower);

        assertEq(prices[0], uint256(usdcPrice));
        assertEq(errorCodes[0], 0);

        assertEq(prices[1], uint256(ethPrice));
        assertEq(errorCodes[1], 0);
    }
}
