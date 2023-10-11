// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { IChainlink } from "contracts/interfaces/external/chainlink/IChainlink.sol";
import { TestBasePriceRouter } from "../TestBasePriceRouter.sol";
import { PriceRouter } from "contracts/oracles/PriceRouter.sol";

contract GetPriceMultiTest is TestBasePriceRouter {
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
        vm.expectRevert(0xe4558fac);
        priceRouter.getPrices(assets, inUSD, getLower);
    }

    function test_getPriceMulti_success() public {
        _addSinglePriceFeed();

        (, int256 usdcPrice, , , ) = IChainlink(_CHAINLINK_USDC_USD)
            .latestRoundData();
        (, int256 ethPrice, , , ) = IChainlink(_CHAINLINK_USDC_ETH)
            .latestRoundData();

        (uint256[] memory prices, uint256[] memory errorCodes) = priceRouter
            .getPrices(assets, inUSD, getLower);

        assertEq(prices[0], uint256(usdcPrice) * 1e10);
        assertEq(errorCodes[0], 0);

        assertEq(prices[1], uint256(ethPrice));
        assertEq(errorCodes[1], 0);
    }
}
