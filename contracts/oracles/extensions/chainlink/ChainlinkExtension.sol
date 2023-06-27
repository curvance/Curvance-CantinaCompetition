// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import { IStaticOracle } from "@mean-finance/uniswap-v3-oracle/solidity/interfaces/IStaticOracle.sol";

import "../../../interfaces/ICentralRegistry.sol";
import "../../../interfaces/IOracleExtension.sol";
import { Extension } from "../ExtensionV2.sol";

contract ChainlinkExtension is Extension {


    constructor(ICentralRegistry _centralRegistry) Extension(_centralRegistry) {}

     /**
     * @notice Called by PriceRouter to price an asset.
     */
    function getPrice(address _asset) external view override returns (priceReturnData memory) {
        priceReturnData memory data = priceReturnData({price:0, hadError:false, inUSD:false});
        return data;
    }

    /**
     * @notice Adds a new supported asset to the extension, can also configure sub assets that the parent asset contain.
     */
    function addAsset(address _asset) external override {

    }

    /**
     * @notice Removes a supported asset from the extension.
     */
    function removeAsset(address _asset) external override {

    }

}
