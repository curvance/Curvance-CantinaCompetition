// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBasePriceRouter } from "../TestBasePriceRouter.sol";
import { WstETHAggregator } from "contracts/oracles/adaptors/wrappedAggregators/WstETHAggregator.sol";
import { ChainlinkAdaptor } from "contracts/oracles/adaptors/chainlink/ChainlinkAdaptor.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { PriceRouter } from "contracts/oracles/PriceRouter.sol";

contract TestWstETHAdaptor is TestBasePriceRouter {
    address private _STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address private _WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    WstETHAggregator aggregator;

    function setUp() public override {
        _fork(18031848);

        _deployCentralRegistry();
        _deployPriceRouter();

        aggregator = new WstETHAggregator(_WSTETH, _STETH, _CHAINLINK_ETH_USD);
    }

    function testReturnsCorrectPrice() public {
        chainlinkAdaptor = new ChainlinkAdaptor(
            ICentralRegistry(address(centralRegistry))
        );
        chainlinkAdaptor.addAsset(_STETH, _CHAINLINK_ETH_USD, 0, true);
        chainlinkAdaptor.addAsset(_WSTETH, address(aggregator), 0, true);
        priceRouter.addApprovedAdaptor(address(chainlinkAdaptor));
        priceRouter.addAssetPriceFeed(_STETH, address(chainlinkAdaptor));
        priceRouter.addAssetPriceFeed(_WSTETH, address(chainlinkAdaptor));

        (uint256 price, uint256 errorCode) = priceRouter.getPrice(
            _WSTETH,
            true,
            false
        );
        assertEq(errorCode, 0);
        assertGt(price, 0);
    }
}
