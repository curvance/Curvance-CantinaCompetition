// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseOracleRouter } from "../TestBaseOracleRouter.sol";
import { WstETHAggregator } from "contracts/oracles/adaptors/wrappedAggregators/WstETHAggregator.sol";
import { ChainlinkAdaptor } from "contracts/oracles/adaptors/chainlink/ChainlinkAdaptor.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { OracleRouter } from "contracts/oracles/OracleRouter.sol";

contract TestWstETHAdaptor is TestBaseOracleRouter {
    address private _STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address private _WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    WstETHAggregator aggregator;

    function setUp() public override {
        _fork(18031848);

        _deployCentralRegistry();
        _deployOracleRouter();

        aggregator = new WstETHAggregator(_WSTETH, _STETH, _CHAINLINK_ETH_USD);
    }

    function testReturnsCorrectPrice() public {
        chainlinkAdaptor = new ChainlinkAdaptor(
            ICentralRegistry(address(centralRegistry))
        );
        chainlinkAdaptor.addAsset(_ETH_ADDRESS, _CHAINLINK_ETH_USD, 0, true);
        chainlinkAdaptor.addAsset(_STETH, _CHAINLINK_ETH_USD, 0, true);
        chainlinkAdaptor.addAsset(_WSTETH, address(aggregator), 0, true);
        oracleRouter.addApprovedAdaptor(address(chainlinkAdaptor));
        oracleRouter.addAssetPriceFeed(
            _ETH_ADDRESS,
            address(chainlinkAdaptor)
        );
        oracleRouter.addAssetPriceFeed(_STETH, address(chainlinkAdaptor));
        oracleRouter.addAssetPriceFeed(_WSTETH, address(chainlinkAdaptor));

        (uint256 price, uint256 errorCode) = oracleRouter.getPrice(
            _WSTETH,
            true,
            false
        );
        assertEq(errorCode, 0);
        assertGt(price, 0);
    }
}
