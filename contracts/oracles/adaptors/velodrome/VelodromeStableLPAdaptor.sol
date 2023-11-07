// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { BaseStableLPAdaptor } from "contracts/oracles/adaptors/utils/BaseStableLPAdaptor.sol";

import { PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IVeloPool } from "contracts/interfaces/external/velodrome/IVeloPool.sol";

contract VelodromeStableLPAdaptor is BaseStableLPAdaptor {
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
    /// @dev https://blog.alphaventuredao.io/fair-lp-token-pricing/
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
            revert VelodromeStableLPAdaptor__AssetIsNotSupported();
        }

        return _getPrice(asset, inUSD, getLower);
    }

    /// @notice Add a Balancer Stable Pool Bpt as an asset.
    /// @dev Should be called before `PriceRotuer:addAssetPriceFeed` is called.
    /// @param asset The address of the bpt to add
    function addAsset(
        address asset
    ) external override onlyElevatedPermissions {
        if (isSupportedAsset[asset]) {
            revert VelodromeStableLPAdaptor__AssetIsAlreadyAdded();
        }
        if (!IVeloPool(asset).stable()) {
            revert VelodromeStableLPAdaptor__AssetIsNotStableLP();
        }

        _addAsset(asset);
    }

    /// @notice Removes a supported asset from the adaptor.
    /// @dev Calls back into price router to notify it of its removal
    function removeAsset(address asset) external override onlyDaoPermissions {
        if (!isSupportedAsset[asset]) {
            revert VelodromeStableLPAdaptor__AssetIsNotSupported();
        }

        _removeAsset(asset);
    }
}
