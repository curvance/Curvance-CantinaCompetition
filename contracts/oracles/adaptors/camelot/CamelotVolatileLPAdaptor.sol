// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { BaseVolatileLPAdaptor } from "contracts/oracles/adaptors/utils/BaseVolatileLPAdaptor.sol";

import { PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { ICamelotPair } from "contracts/interfaces/external/camelot/ICamelotPair.sol";

contract CamelotVolatileLPAdaptor is BaseVolatileLPAdaptor {
    /// EVENTS ///

    event CamelotVolatileLPAssetAdded(
        address asset,
        AdaptorData assetConfig
    );

    event CamelotVolatileLPAssetRemoved(address asset);

    /// ERRORS ///

    error CamelotVolatileLPAdaptor__AssetIsNotSupported();
    error CamelotVolatileLPAdaptor__AssetIsAlreadyAdded();
    error CamelotVolatileLPAdaptor__AssetIsNotVolatileLP();

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_
    ) BaseVolatileLPAdaptor(centralRegistry_) {}

    /// EXTERNAL FUNCTIONS ///

    /// @notice Called during pricing operations.
    /// @param asset The bpt being priced
    /// @param inUSD Indicates whether we want the price in USD or ETH
    /// @param getLower Since this adaptor calls back into the price router
    ///                 it needs to know if it should be working with the
    ///                 upper or lower prices of assets
    function getPrice(
        address asset,
        bool inUSD,
        bool getLower
    ) external view override returns (PriceReturnData memory) {
        if (!isSupportedAsset[asset]) {
            revert CamelotVolatileLPAdaptor__AssetIsNotSupported();
        }

        return _getPrice(asset, inUSD, getLower);
    }

    /// @notice Add a Balancer Stable Pool Bpt as an asset.
    /// @dev Should be called before `PriceRotuer:addAssetPriceFeed` is called.
    /// @param asset The address of the bpt to add
    function addAsset(
        address asset
    ) external override {
        _checkElevatedPermissions();

        if (isSupportedAsset[asset]) {
            revert CamelotVolatileLPAdaptor__AssetIsAlreadyAdded();
        }
        if (ICamelotPair(asset).stableSwap()) {
            revert CamelotVolatileLPAdaptor__AssetIsNotVolatileLP();
        }

        AdaptorData memory data = _addAsset(asset);
        emit CamelotVolatileLPAssetAdded(asset, data);
    }

    /// @notice Removes a supported asset from the adaptor.
    /// @dev Calls back into price router to notify it of its removal
    function removeAsset(
        address asset
    ) external virtual override {
        _checkElevatedPermissions();

        if (!isSupportedAsset[asset]) {
            revert CamelotVolatileLPAdaptor__AssetIsNotSupported();
        }

        _removeAsset(asset);
        emit CamelotVolatileLPAssetRemoved(asset);
    }
}
