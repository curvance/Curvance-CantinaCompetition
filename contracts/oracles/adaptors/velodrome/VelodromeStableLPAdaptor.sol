// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { BaseStableLPAdaptor } from "contracts/oracles/adaptors/utils/BaseStableLPAdaptor.sol";

import { PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IVeloPool } from "contracts/interfaces/external/velodrome/IVeloPool.sol";

contract VelodromeStableLPAdaptor is BaseStableLPAdaptor {
    /// EVENTS ///

    event VelodromeStableLPAssetAdded(
        address asset,
        AdaptorData assetConfig
    );

    event VelodromeStableLPAssetRemoved(address asset);

    /// ERRORS ///

    error VelodromeStableLPAdaptor__AssetIsNotSupported();
    error VelodromeStableLPAdaptor__AssetIsAlreadyAdded();
    error VelodromeStableLPAdaptor__AssetIsNotStableLP();

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
            revert VelodromeStableLPAdaptor__AssetIsNotSupported();
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
            revert VelodromeStableLPAdaptor__AssetIsAlreadyAdded();
        }
        if (!IVeloPool(asset).stable()) {
            revert VelodromeStableLPAdaptor__AssetIsNotStableLP();
        }
        
        AdaptorData memory data = _addAsset(asset);
        emit VelodromeStableLPAssetAdded(asset, data);
    }

    /// @notice Removes a supported asset from the adaptor.
    /// @dev Calls back into oracle router to notify it of its removal.
    ///      Requires that `asset` is currently supported.
    /// @param asset The address of the supported asset to remove from
    ///              the adaptor.
    function removeAsset(address asset) external override {
        _checkElevatedPermissions();

        if (!isSupportedAsset[asset]) {
            revert VelodromeStableLPAdaptor__AssetIsNotSupported();
        }

        _removeAsset(asset);
        emit VelodromeStableLPAssetRemoved(asset);
    }
}
