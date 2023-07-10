// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import { BaseOracleAdaptor } from "../BaseOracleAdaptor.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IOracleAdaptor, PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";

contract ChainlinkAdaptor is BaseOracleAdaptor {
    constructor(
        ICentralRegistry _centralRegistry
    ) BaseOracleAdaptor(_centralRegistry) {}

    /// @notice Called by PriceRouter to price an asset.
    function getPrice(
        address _asset,
        bool _isUsd,
        bool _getLower
    ) external view override returns (PriceReturnData memory) {
        PriceReturnData memory data = PriceReturnData({
            price: 0,
            hadError: false,
            inUSD: false
        });
        return data;
    }

    /// @notice Removes a supported asset from the adaptor.
    function removeAsset(address _asset) external override {}
}
