// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import { BaseOracleAdaptor } from "contracts/oracles/adaptors/BaseOracleAdaptor.sol";
import { Bytes32Helper } from "contracts/libraries/Bytes32Helper.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IOracleRouter } from "contracts/interfaces/IOracleRouter.sol";
import { PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";

abstract contract BaseRedstoneCoreAdaptor is BaseOracleAdaptor {
    /// TYPES ///

    /// @notice Stores configuration data for Redstone price sources.
    struct AdaptorData {
        /// @notice Whether the asset is configured or not.
        /// @dev    false = unconfigured; true = configured.
        bool isConfigured;
        /// @notice The bytes32 encoded hash of the price feed.
        bytes32 symbolHash;
        /// @notice The max valid price of the asset.
        uint256 max;
        /// @notice The number of decimals in the redstone price feed.
        /// @dev We save this as a uint256 so we do not need to convert from
        ///      uint8 -> uint256 at runtime.
        uint256 decimals;
    }

    /// STORAGE ///

    /// @notice Redstone Adaptor Data for pricing in ETH
    mapping(address => AdaptorData) public adaptorDataNonUSD;

    /// @notice Redstone Adaptor Data for pricing in USD
    mapping(address => AdaptorData) public adaptorDataUSD;

    /// EVENTS ///

    event RedstoneCoreAssetAdded(address asset, AdaptorData assetConfig);
    event RedstoneCoreAssetRemoved(address asset);

    /// ERRORS ///

    error BaseRedstoneCoreAdaptor__AssetIsNotSupported();
    error BaseRedstoneCoreAdaptor__SymbolHashError();
    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_
    ) BaseOracleAdaptor(centralRegistry_) {}

    /// EXTERNAL FUNCTIONS ///

    /// @notice Retrieves the price of a given asset.
    /// @dev Uses Redstone Core oracles to fetch the price data.
    ///      Price is returned in USD or ETH depending on 'inUSD' parameter.
    /// @param asset The address of the asset for which the price is needed.
    /// @param inUSD A boolean to determine if the price should be returned in
    ///              USD or not.
    /// @return PriceReturnData A structure containing the price, error status,
    ///                         and the quote format of the price.
    function getPrice(
        address asset,
        bool inUSD,
        bool
    ) external view override returns (PriceReturnData memory) {
        if (!isSupportedAsset[asset]) {
            revert BaseRedstoneCoreAdaptor__AssetIsNotSupported();
        }

        if (inUSD) {
            return _getPriceInUSD(asset);
        }

        return _getPriceInETH(asset);
    }

    /// @notice Add a Redstone Core Price Feed as an asset.
    /// @dev Should be called before `OracleRouter:addAssetPriceFeed`
    ///      is called.
    /// @param asset The address of the token to add pricing for.
    /// @param inUSD Whether the price feed is in USD (inUSD = true)
    ///              or ETH (inUSD = false).
    /// @param decimals The number of decimals the redstone core feed
    ///                 prices in.
    function addAsset(
        address asset, 
        bool inUSD,
        uint8 decimals
    ) external {
        _checkElevatedPermissions();

        bytes32 symbolHash;
        if (inUSD) {
            // Redstone Core does not append anything at the end of USD
            // denominated feeds, so we use toBytes32 here.
            symbolHash = Bytes32Helper._toBytes32(asset);
        } else {
            // Redstone Core appends "/ETH" at the end of ETH denominated
            // feeds, so we use toBytes32WithETH here.
            symbolHash = Bytes32Helper._toBytes32WithETH(asset);
        }

        AdaptorData storage data;

        if (inUSD) {
            data = adaptorDataUSD[asset];
        } else {
            data = adaptorDataNonUSD[asset];
        }

        // If decimals == 0 we want default 8 decimals that
        // redstone typically returns in.
        if (decimals == 0) {
            data.decimals = 8;
        } else {
            // Otherwise coerce uint8 to uint256 for cheaper
            // runtime conversion.
            data.decimals = uint256(decimals);
        }

        // Add a ~10% buffer to maximum price allowed from redstone can stop 
        // updating its price before/above the min/max price.
        // We use a maximum buffered price of 2^192 - 1 since redstone core
        // reports pricing in 8 decimal format, requiring multiplication by
        // 10e10 to standardize to 18 decimal format, which could overflow 
        // when trying to save the final value into an uint240.
        data.max = (type(uint192).max * 9) / 10;
        data.symbolHash = symbolHash;
        data.isConfigured = true;
        isSupportedAsset[asset] = true;

        emit RedstoneCoreAssetAdded(asset, data);
    }

    /// @notice Removes a supported asset from the adaptor.
    /// @dev Calls back into oracle router to notify it of its removal.
    /// @param asset The address of the supported asset to remove from
    ///              the adaptor.
    function removeAsset(address asset) external override {
        _checkElevatedPermissions();

        if (!isSupportedAsset[asset]) {
            revert BaseRedstoneCoreAdaptor__AssetIsNotSupported();
        }

        // Notify the adaptor to stop supporting the asset.
        delete isSupportedAsset[asset];

        // Wipe config mapping entries for a gas refund.
        delete adaptorDataUSD[asset];
        delete adaptorDataNonUSD[asset];

        // Notify the oracle router that we are going to stop supporting
        // the asset.
        IOracleRouter(centralRegistry.oracleRouter()).notifyFeedRemoval(asset);
        
        emit RedstoneCoreAssetRemoved(asset);
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Retrieves the price of a given asset in USD.
    /// @param asset The address of the asset for which the price is needed.
    /// @return A structure containing the price, error status,
    ///         and the quote format of the price (USD).
    function _getPriceInUSD(
        address asset
    ) internal view returns (PriceReturnData memory) {
        if (adaptorDataUSD[asset].isConfigured) {
            return _parseData(adaptorDataUSD[asset], true);
        }

        return _parseData(adaptorDataNonUSD[asset], false);
    }

    /// @notice Retrieves the price of a given asset in ETH.
    /// @param asset The address of the asset for which the price is needed.
    /// @return A structure containing the price, error status,
    ///         and the quote format of the price (ETH).
    function _getPriceInETH(
        address asset
    ) internal view returns (PriceReturnData memory) {
        if (adaptorDataNonUSD[asset].isConfigured) {
            return _parseData(adaptorDataNonUSD[asset], false);
        }

        return _parseData(adaptorDataUSD[asset], true);
    }

    /// @notice Extracts the redstone core feed data for pricing of an asset.
    /// @dev Calls read() from Redstone Core to get the latest data
    ///      for pricing and staleness.
    /// @param data Redstone Core feed details.
    /// @param inUSD A boolean to denote if the price is in USD.
    /// @return pData A structure containing the price, error status,
    ///               and the currency of the price.
    function _parseData(
        AdaptorData memory data,
        bool inUSD
    ) internal view returns (PriceReturnData memory pData) {
        pData.inUSD = inUSD;
        uint256 price = _extractPrice(data.symbolHash);

        // If we got a price of 0, bubble up an error immediately.
        if (price == 0) {
            pData.hadError = true;
            return pData;
        }

        uint256 quoteDecimals = data.decimals;
        if (quoteDecimals != 18) {
            // Decimals are < 18 so we need to multiply up to coerce to
            // 18 decimals.
            if (quoteDecimals < 18) {
                price = price * (10 ** (18 - quoteDecimals));
            } else {
                // Decimals are > 18 so we need to multiply down to coerce to
                // 18 decimals.
                price = price / (10 ** (quoteDecimals - 18));
            }
        }

        pData.hadError = _verifyData(price, data.max);

        if (!pData.hadError) {
            pData.price = uint240(price);
        }
    }

    /// @notice Validates the feed data based on various constraints.
    /// @dev Checks if the value is within a specific range
    ///      and if the data is not outdated.
    /// @param value The value that is retrieved from the feed data.
    /// @param max The maximum limit of the value.
    /// @return A boolean indicating whether the feed data had an error
    ///         (true = error, false = no error).
    function _verifyData(
        uint256 value,
        uint256 max
    ) internal pure returns (bool) {
        if (value > max) {
            return true;
        }

        // We typically check for feed data staleness through a heartbeat
        // check, but redstone naturally checks timestamp through its msg.data
        // read, so we do not need to check again here.

        return false;
    }

    /// INTERNAL FUNCTIONS TO OVERRIDE ///
    function  _extractPrice(bytes32 symbolHash) internal virtual view returns (uint256);

}
