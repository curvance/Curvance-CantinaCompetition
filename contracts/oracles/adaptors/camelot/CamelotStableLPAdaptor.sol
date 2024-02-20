// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { BaseStableLPAdaptor } from "contracts/oracles/adaptors/uniV2Base/BaseStableLPAdaptor.sol";

import { PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { ICamelotPair } from "contracts/interfaces/external/camelot/ICamelotPair.sol";

contract CamelotStableLPAdaptor is BaseStableLPAdaptor {
    /// EVENTS ///

    event CamelotStableLPAssetAdded(
        address asset, 
        AdaptorData assetConfig, 
        bool isUpdate
    );
    event CamelotStableLPAssetRemoved(address asset);

    /// ERRORS ///

    error CamelotStableLPAdaptor__AssetIsNotStableLP();

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_
    ) BaseStableLPAdaptor(centralRegistry_) {}

    /// EXTERNAL FUNCTIONS ///

    /// @notice Adds pricing support for `asset`, new Camelot Stable LP.
    /// @dev Should be called before `OracleRouter:addAssetPriceFeed`
    ///      is called.
    /// @param asset The address of the lp token to add pricing support for.
    function addAsset(
        address asset
    ) external override {
        _checkElevatedPermissions();

        if (!ICamelotPair(asset).stableSwap()) {
            revert CamelotStableLPAdaptor__AssetIsNotStableLP();
        }

        // Check whether this is new or updated support for `asset`.
        bool isUpdate;
        if (isSupportedAsset[asset]) {
            isUpdate = true;
        }

        AdaptorData memory data = _addAsset(asset);
        emit CamelotStableLPAssetAdded(asset, data, isUpdate);
    }

    /// @notice Removes a supported asset from the adaptor.
    /// @dev Calls back into Oracle Router to notify it of its removal.
    ///      Requires that `asset` is currently supported.
    /// @param asset The address of the supported asset to remove from
    ///              the adaptor.
    function removeAsset(address asset) external override {
        _checkElevatedPermissions();

        _removeAsset(asset);
        emit CamelotStableLPAssetRemoved(asset);
    }
}
