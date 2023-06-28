// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import { IStaticOracle } from "contracts/interfaces/external/uniswap/IStaticOracle.sol";

import "contracts/interfaces/ICentralRegistry.sol";
import "../../../interfaces/IOracleAdaptor.sol";
import { BaseOracleAdaptor } from "../BaseOracleAdaptor.sol";

contract ChainlinkAdaptor is BaseOracleAdaptor {
    constructor(ICentralRegistry _centralRegistry)
        BaseOracleAdaptor(_centralRegistry)
    {}

    /**
     * @notice Called by PriceRouter to price an asset.
     */
    function getPrice(address _asset)
        external
        view
        override
        returns (priceReturnData memory)
    {
        priceReturnData memory data = priceReturnData({
            price: 0,
            hadError: false,
            inUSD: false
        });
        return data;
    }

    /**
     * @notice Adds a new supported asset to the adaptor, can also configure sub assets that the parent asset contain.
     */
    function addAsset(address _asset) external override {}

    /**
     * @notice Removes a supported asset from the adaptor.
     */
    function removeAsset(address _asset) external override {}
}
