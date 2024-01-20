// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { BaseOracleAdaptor } from "contracts/oracles/adaptors/BaseOracleAdaptor.sol";
import { Bytes32Helper } from "contracts/libraries/Bytes32Helper.sol";
import { WAD } from "contracts/libraries/Constants.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IOracleRouter } from "contracts/interfaces/IOracleRouter.sol";
import { PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";
import { IProxy } from "contracts/interfaces/external/api3/IProxy.sol";

contract Api3Adaptor is BaseOracleAdaptor {
    /// TYPES ///

    /// @notice Stores configuration data for API3 price sources.
    struct AdaptorData {
        /// @notice The current proxy's feed address.
        IProxy proxyFeed;
        /// @notice The bytes32 encoded name hash of the price feed.
        bytes32 dapiNameHash;
        /// @notice Whether the asset is configured or not.
        /// @dev    false = unconfigured; true = configured.
        bool isConfigured;
        /// @notice heartbeat the max amount of time between price updates.
        /// @dev    0 defaults to using DEFAULT_HEART_BEAT.
        uint256 heartbeat;
        /// @notice max the max valid price of the asset.
        /// @dev    0 defaults to use proxy max price reduced by ~10%.
        uint256 max;
    }

    /// CONSTANTS ///

    /// @notice If zero is specified for an Api3 asset heartbeat,
    ///         this value is used instead.
    uint256 public constant DEFAULT_HEART_BEAT = 1 days;

    /// STORAGE ///

    /// @notice Api3 Adaptor Data for pricing in ETH.
    mapping(address => AdaptorData) public adaptorDataNonUSD;

    /// @notice Api3 Adaptor Data for pricing in USD.
    mapping(address => AdaptorData) public adaptorDataUSD;

    /// EVENTS ///

    event Api3AssetAdded(address asset, AdaptorData assetConfig);
    event Api3AssetRemoved(address asset);

    /// ERRORS ///

    error Api3Adaptor__AssetIsNotSupported();
    error Api3Adaptor__DAPINameHashError();
    error Api3Adaptor__InvalidHeartbeat();

    /// CONSTRUCTOR ///

    /// @param centralRegistry_ The address of central registry.
    constructor(
        ICentralRegistry centralRegistry_
    ) BaseOracleAdaptor(centralRegistry_) {}

    /// EXTERNAL FUNCTIONS ///

    /// @notice Retrieves the price of a given asset.
    /// @dev Uses Api3 oracles to fetch the price data.
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
            revert Api3Adaptor__AssetIsNotSupported();
        }

        if (inUSD) {
            return _getPriceInUSD(asset);
        }

        return _getPriceInETH(asset);
    }

    /// @notice Add a Api3 Price Feed as an asset.
    /// @dev Should be called before `OracleRouter:addAssetPriceFeed` is called.
    /// @param asset The address of the token to add pricing for.
    /// @param proxyFeed Api3 proxy feed to use for pricing `asset`.
    /// @param heartbeat Api3 heartbeat to use when validating prices
    ///                  for `asset`. 0 = `DEFAULT_HEART_BEAT`.
    /// @param inUSD Whether the price feed is in USD (inUSD = true)
    ///              or ETH (inUSD = false).
    function addAsset(
        address asset, 
        address proxyFeed, 
        uint256 heartbeat, 
        bool inUSD
    ) external {
        _checkElevatedPermissions();

        if (heartbeat != 0) {
            if (heartbeat > DEFAULT_HEART_BEAT) {
                revert Api3Adaptor__InvalidHeartbeat();
            }
        }

        bytes32 dapiName;
        if (inUSD) {
            // API3 appends "/USD" at the end of USD denominated feeds,
            // so we use toBytes32WithUSD here.
            dapiName = Bytes32Helper._toBytes32WithUSD(asset);
        } else {
            // API3 appends "/ETH" at the end of ETH denominated feeds,
            // so we use toBytes32WithETH here.
            dapiName = Bytes32Helper._toBytes32WithETH(asset);
        }
        bytes32 dapiNameHash = keccak256(abi.encodePacked(dapiName));

        // Validate that the dAPI name and corresponding hash generated off
        // the symbol and denomation match the proxyFeed documented form.
        if (dapiNameHash != IProxy(proxyFeed).dapiNameHash()) {
            revert Api3Adaptor__DAPINameHashError();
        }

        AdaptorData storage adaptorData;

        if (inUSD) {
            adaptorData = adaptorDataUSD[asset];
        } else {
            adaptorData = adaptorDataNonUSD[asset];
        }

        adaptorData.heartbeat = heartbeat != 0
            ? heartbeat
            : DEFAULT_HEART_BEAT;

        // Add a ~10% buffer to maximum price allowed from Api3 can stop 
        // updating its price before/above the min/max price. We use a maximum
        // buffered price of 2^224 - 1, which could overflow when trying to
        // save the final value into an uint240.
        adaptorData.max = (uint256(int256(type(int224).max)) * 9) / 10;
        adaptorData.dapiNameHash = dapiNameHash;
        adaptorData.proxyFeed = IProxy(proxyFeed);
        adaptorData.isConfigured = true;
        isSupportedAsset[asset] = true;

        emit Api3AssetAdded(asset, adaptorData);
    }

    /// @notice Removes a supported asset from the adaptor.
    /// @dev Calls back into price router to notify it of its removal.
    function removeAsset(address asset) external override {
        _checkElevatedPermissions();

        if (!isSupportedAsset[asset]) {
            revert Api3Adaptor__AssetIsNotSupported();
        }

        // Notify the adaptor to stop supporting the asset.
        delete isSupportedAsset[asset];

        // Wipe config mapping entries for a gas refund.
        delete adaptorDataUSD[asset];
        delete adaptorDataNonUSD[asset];

        // Notify the price router that we are going to stop supporting the asset.
        IOracleRouter(centralRegistry.oracleRouter()).notifyFeedRemoval(asset);
        
        emit Api3AssetRemoved(asset);
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

    /// @notice Parses the api3 feed data for pricing of an asset.
    /// @dev Calls read() from Api3 to get the latest data
    ///      for pricing and staleness.
    /// @param data Api3 feed details.
    /// @param inUSD A boolean to denote if the price is in USD.
    /// @return pData A structure containing the price, error status,
    ///               and the currency of the price.
    function _parseData(
        AdaptorData memory data,
        bool inUSD
    ) internal view returns (PriceReturnData memory pData) {
        (int256 price, uint256 updatedAt) = data.proxyFeed.read();

        // If we got a price of 0 or less, bubble up an error immediately.
        if (price <= 0) {
            pData.hadError = true;
            return pData;
        }

        pData.price = uint240(uint256(price));
        pData.hadError = _verifyData(
                        uint256(price),
                        updatedAt,
                        data.max,
                        data.heartbeat
                    );
        pData.inUSD = inUSD;
    }

    /// @notice Validates the feed data based on various constraints.
    /// @dev Checks if the value is within a specific range
    ///      and if the data is not outdated.
    /// @param value The value that is retrieved from the feed data.
    /// @param timestamp The time at which the value was last updated.
    /// @param max The maximum limit of the value.
    /// @param heartbeat The maximum allowed time difference between
    ///                  current time and 'timestamp'.
    /// @return A boolean indicating whether the feed data had an error
    ///         (true = error, false = no error).
    function _verifyData(
        uint256 value,
        uint256 timestamp,
        uint256 max,
        uint256 heartbeat
    ) internal view returns (bool) {
        if (value > max) {
            return true;
        }

        if (block.timestamp - timestamp > heartbeat) {
            return true;
        }

        return false;
    }
}
