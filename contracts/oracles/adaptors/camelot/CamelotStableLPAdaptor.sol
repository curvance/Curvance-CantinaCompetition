// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { BaseStableLPAdaptor } from "contracts/oracles/adaptors/utils/BaseStableLPAdaptor.sol";

import { PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { ICamelotPair } from "contracts/interfaces/external/camelot/ICamelotPair.sol";

contract CamelotStableLPAdaptor is BaseStableLPAdaptor {
    /// EVENTS ///

    event CamelotStableLPAssetAdded(address asset, AdaptorData assetConfig);

    event CamelotStableLPAssetRemoved(address asset);

    /// ERRORS ///

    error CamelotStableLPAdaptor__AssetIsNotSupported();
    error CamelotStableLPAdaptor__AssetIsAlreadyAdded();
    error CamelotStableLPAdaptor__AssetIsNotStableLP();

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_
    ) BaseStableLPAdaptor(centralRegistry_) {}

    /// EXTERNAL FUNCTIONS ///

    /// @notice Called during pricing operations.
    /// @param asset The bpt being priced
    /// @param inUSD Indicates whether we want the price in USD or ETH
    /// @param getLower Since this adaptor calls back into the oracle router
    ///                 it needs to know if it should be working with the
    ///                 upper or lower prices of assets
    function getPrice(
        address asset,
        bool inUSD,
        bool getLower
    ) external view override returns (PriceReturnData memory) {
        if (!isSupportedAsset[asset]) {
            revert CamelotStableLPAdaptor__AssetIsNotSupported();
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
            revert CamelotStableLPAdaptor__AssetIsAlreadyAdded();
        }
        if (!ICamelotPair(asset).stableSwap()) {
            revert CamelotStableLPAdaptor__AssetIsNotStableLP();
        }

        AdaptorData memory data = _addAsset(asset);
        emit CamelotStableLPAssetAdded(asset, data);
    }

    /// @notice Removes a supported asset from the adaptor.
    /// @dev Calls back into oracle router to notify it of its removal.
    ///      Requires that `asset` is currently supported.
    /// @param asset The address of the supported asset to remove from
    ///              the adaptor.
    function removeAsset(address asset) external override {
        _checkElevatedPermissions();

        if (!isSupportedAsset[asset]) {
            revert CamelotStableLPAdaptor__AssetIsNotSupported();
        }

        _removeAsset(asset);
        emit CamelotStableLPAssetRemoved(asset);
    }
}
