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

    /// @notice Retrieves the price of a given Camelot Volatile LP.
    /// @dev Price is returned in USD or ETH depending on 'inUSD' parameter.
    /// @param asset The address of the asset for which the price is needed.
    /// @param inUSD A boolean to determine if the price should be returned in
    ///              USD or not.
    /// @param getLower A boolean to determine if lower of two oracle prices
    ///                 should be retrieved.
    /// @return A structure containing the price, error status,
    ///         and the quote format of the price.
    function getPrice(
        address asset,
        bool inUSD,
        bool getLower
    ) external view override returns (PriceReturnData memory) {
        // Validate we support pricing `asset`.
        if (!isSupportedAsset[asset]) {
            revert CamelotVolatileLPAdaptor__AssetIsNotSupported();
        }

        return _getPrice(asset, inUSD, getLower);
    }

    /// @notice Adds pricing support for `asset`, a new Camelot Volatile LP.
    /// @dev Should be called before `OracleRouter:addAssetPriceFeed`
    ///      is called.
    /// @param asset The address of the token to add pricing support for.
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
    /// @dev Calls back into oracle router to notify it of its removal.
    ///      Requires that `asset` is currently supported.
    /// @param asset The address of the supported asset to remove from
    ///              the adaptor.
    function removeAsset(address asset) external virtual override {
        _checkElevatedPermissions();

        // Validate that `asset` is currently supported.
        if (!isSupportedAsset[asset]) {
            revert CamelotVolatileLPAdaptor__AssetIsNotSupported();
        }

        _removeAsset(asset);
        emit CamelotVolatileLPAssetRemoved(asset);
    }
}
