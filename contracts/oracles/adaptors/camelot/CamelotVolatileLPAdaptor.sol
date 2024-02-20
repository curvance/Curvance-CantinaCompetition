// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { BaseVolatileLPAdaptor } from "contracts/oracles/adaptors/uniV2Base/BaseVolatileLPAdaptor.sol";

import { PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { ICamelotPair } from "contracts/interfaces/external/camelot/ICamelotPair.sol";

contract CamelotVolatileLPAdaptor is BaseVolatileLPAdaptor {
    /// EVENTS ///

    event CamelotVolatileLPAssetAdded(
        address asset, 
        AdaptorData assetConfig, 
        bool isUpdate
    );
    event CamelotVolatileLPAssetRemoved(address asset);

    /// ERRORS ///

    error CamelotVolatileLPAdaptor__AssetIsNotVolatileLP();

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_
    ) BaseVolatileLPAdaptor(centralRegistry_) {}

    /// EXTERNAL FUNCTIONS ///

    /// @notice Adds pricing support for `asset`, a new Camelot Volatile LP.
    /// @dev Should be called before `OracleRouter:addAssetPriceFeed`
    ///      is called.
    /// @param asset The address of the lp token to add pricing support for.
    function addAsset(
        address asset
    ) external override {
        _checkElevatedPermissions();

        if (ICamelotPair(asset).stableSwap()) {
            revert CamelotVolatileLPAdaptor__AssetIsNotVolatileLP();
        }

        // Check whether this is new or updated support for `asset`.
        bool isUpdate;
        if (isSupportedAsset[asset]) {
            isUpdate = true;
        }

        AdaptorData memory data = _addAsset(asset);
        emit CamelotVolatileLPAssetAdded(asset, data, isUpdate);
    }

    /// @notice Removes a supported asset from the adaptor.
    /// @dev Calls back into Oracle Router to notify it of its removal.
    ///      Requires that `asset` is currently supported.
    /// @param asset The address of the supported asset to remove from
    ///              the adaptor.
    function removeAsset(address asset) external virtual override {
        _checkElevatedPermissions();

        _removeAsset(asset);
        emit CamelotVolatileLPAssetRemoved(asset);
    }
}
