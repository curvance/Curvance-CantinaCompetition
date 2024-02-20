// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { BaseOracleAdaptor } from "contracts/oracles/adaptors/BaseOracleAdaptor.sol";
import { WAD } from "contracts/libraries/Constants.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IOracleRouter } from "contracts/interfaces/IOracleRouter.sol";
import { PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";
import { IChainlink } from "contracts/interfaces/external/chainlink/IChainlink.sol";

contract ChainlinkAdaptor is BaseOracleAdaptor {
    /// TYPES ///

    /// @notice Stores configuration data for Chainlink price sources.
    /// @param aggregator The current phase's aggregator address.
    /// @param isConfigured Whether the asset is configured or not.
    ///                     false = unconfigured; true = configured.
    /// @param decimals Returns the number of decimals the aggregator
    ///                 responds with.
    /// @param heartbeat The max amount of time between price updates.
    ///                  0 defaults to using DEFAULT_HEART_BEAT.
    /// @param max The maximum valid price of the asset.
    ///            0 defaults to use proxy max price reduced by ~10%.
    /// @param min The minimum valid price of the asset.
    ///            0 defaults to use proxy min price increased by ~10%.
    struct AdaptorData {
        IChainlink aggregator;
        bool isConfigured;
        uint256 decimals;
        uint256 heartbeat;
        uint256 max;
        uint256 min;
    }

    /// CONSTANTS ///

    /// @notice If zero is specified for a Chainlink asset heartbeat,
    ///         this value is used instead.
    /// @dev    1 days = 24 hours = 1,440 minutes = 86,400 seconds.
    uint256 public constant DEFAULT_HEART_BEAT = 1 days;

    /// STORAGE ///

    /// @notice Adaptor configuration data for pricing an asset in gas token.
    /// @dev Chainlink Adaptor Data for pricing in gas token.
    mapping(address => AdaptorData) public adaptorDataNonUSD;

    /// @notice Adaptor configuration data for pricing an asset in USD.
    /// @dev Chainlink Adaptor Data for pricing in USD.
    mapping(address => AdaptorData) public adaptorDataUSD;

    /// EVENTS ///

    event ChainlinkAssetAdded(
        address asset, 
        AdaptorData assetConfig, 
        bool isUpdate
    );
    event ChainlinkAssetRemoved(address asset);

    /// ERRORS ///

    error ChainlinkAdaptor__AssetIsNotSupported();
    error ChainlinkAdaptor__InvalidHeartbeat();
    error ChainlinkAdaptor__InvalidMinMaxConfig();

    /// CONSTRUCTOR ///

    /// @param centralRegistry_ The address of central registry.
    constructor(
        ICentralRegistry centralRegistry_
    ) BaseOracleAdaptor(centralRegistry_) {}

    /// EXTERNAL FUNCTIONS ///

    /// @notice Retrieves the price of a given asset.
    /// @dev Uses Chainlink oracles to fetch the price data.
    ///      Price is returned in USD or ETH depending on 'inUSD' parameter.
    /// @param asset The address of the asset for which the price is needed.
    /// @param inUSD A boolean to determine if the price should be returned in
    ///              USD or not.
    /// @return A structure containing the price, error status,
    ///         and the quote format of the price.
    function getPrice(
        address asset,
        bool inUSD,
        bool  /* getLower */
    ) external view override returns (PriceReturnData memory) {
        // Validate we support pricing `asset`.
        if (!isSupportedAsset[asset]) {
            revert ChainlinkAdaptor__AssetIsNotSupported();
        }

        // Check whether we want the pricing in USD first, 
        // otherwise price in terms of the gas token.
        if (inUSD) {
            return _getPriceInUSD(asset);
        }

        return _getPriceInETH(asset);
    }

    /// @notice Adds pricing support for `asset` via a new Chainlink feed.
    /// @dev Should be called before `OracleRouter:addAssetPriceFeed`
    ///      is called.
    /// @param asset The address of the token to add pricing support for.
    /// @param aggregator Chainlink aggregator to use for pricing `asset`.
    /// @param heartbeat Chainlink heartbeat to use when validating prices
    ///                  for `asset`. 0 = `DEFAULT_HEART_BEAT`.
    /// @param inUSD Whether the price feed is in USD (inUSD = true)
    ///              or ETH (inUSD = false).
    function addAsset(
        address asset, 
        address aggregator, 
        uint256 heartbeat, 
        bool inUSD
    ) external {
        _checkElevatedPermissions();

        if (heartbeat != 0) {
            if (heartbeat > DEFAULT_HEART_BEAT) {
                revert ChainlinkAdaptor__InvalidHeartbeat();
            }
        }

        // Use Chainlink to get the min and max of the asset.
        IChainlink feedAggregator = IChainlink(
            IChainlink(aggregator).aggregator()
        );

        // Query Max and Min feed prices from Chainlink aggregator.
        uint256 maxFromChainlink = uint256(
            uint192(feedAggregator.maxAnswer())
        );
        uint256 minFromChainklink = uint256(
            uint192(feedAggregator.minAnswer())
        );

        // Add a ~10% buffer to minimum and maximum price from Chainlink
        // because Chainlink can stop updating its price before/above
        // the min/max price.
        uint256 bufferedMaxPrice = (maxFromChainlink * 9) / 10;
        uint256 bufferedMinPrice = (minFromChainklink * 11) / 10;

        // If the buffered max price is above uint240 its theoretically
        // possible to get a price which would lose precision on uint240
        // conversion, which we need to protect against in getPrice() so
        // we can add a second protective layer here.
        if (bufferedMaxPrice > type(uint240).max) {
            bufferedMaxPrice = type(uint240).max;
        }

        if (bufferedMinPrice >= bufferedMaxPrice) {
            revert ChainlinkAdaptor__InvalidMinMaxConfig();
        }

        AdaptorData storage data;

        if (inUSD) {
            data = adaptorDataUSD[asset];
        } else {
            data = adaptorDataNonUSD[asset];
        }

        // Save adaptor data and update mapping that we support `asset` now.
        data.decimals = feedAggregator.decimals();
        data.max = bufferedMaxPrice;
        data.min = bufferedMinPrice;
        data.heartbeat = heartbeat != 0
            ? heartbeat
            : DEFAULT_HEART_BEAT;
        data.aggregator = IChainlink(aggregator);
        data.isConfigured = true;

        // Check whether this is new or updated support for `asset`.
        bool isUpdate;
        if (isSupportedAsset[asset]) {
            isUpdate = true;
        }

        isSupportedAsset[asset] = true;
        emit ChainlinkAssetAdded(asset, data, isUpdate);
    }

    /// @notice Removes a supported asset from the adaptor.
    /// @dev Calls back into Oracle Router to notify it of its removal.
    ///      Requires that `asset` is currently supported.
    /// @param asset The address of the supported asset to remove from
    ///              the adaptor.
    function removeAsset(address asset) external override {
        _checkElevatedPermissions();

        // Validate that `asset` is currently supported.
        if (!isSupportedAsset[asset]) {
            revert ChainlinkAdaptor__AssetIsNotSupported();
        }

        // Notify the adaptor to stop supporting the asset.
        delete isSupportedAsset[asset];

        // Wipe config mapping entries for a gas refund.
        delete adaptorDataUSD[asset];
        delete adaptorDataNonUSD[asset];

        // Notify the Oracle Router that we are going to stop supporting
        // the asset.
        IOracleRouter(centralRegistry.oracleRouter()).notifyFeedRemoval(asset);
        emit ChainlinkAssetRemoved(asset);
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

    /// @notice Parses the chainlink feed data for pricing of an asset.
    /// @dev Calls latestRoundData() from Chainlink to get the latest data
    ///      for pricing and staleness.
    /// @param data Chainlink feed details.
    /// @param inUSD A boolean to denote if the price is in USD.
    /// @return pData A structure containing the price, error status,
    ///               and the currency of the price.
    function _parseData(
        AdaptorData memory data,
        bool inUSD
    ) internal view returns (PriceReturnData memory pData) {
        pData.inUSD = inUSD;
        if (!IOracleRouter(centralRegistry.oracleRouter()).isSequencerValid()) {
            pData.hadError = true;
            return pData;
        }

        (, int256 price, , uint256 updatedAt, ) = IChainlink(data.aggregator)
            .latestRoundData();

        // If we got a price of 0 or less, bubble up an error immediately.
        if (price <= 0) {
            pData.hadError = true;
            return pData;
        }

        uint256 newPrice = (uint256(price) * WAD) / (10 ** data.decimals);

        pData.price = uint240(newPrice);
        pData.hadError = _verifyData(
                        uint256(price),
                        updatedAt,
                        data.max,
                        data.min,
                        data.heartbeat
                    );
    }

    /// @notice Validates the feed data based on various constraints.
    /// @dev Checks if the value is within a specific range
    ///      and if the data is not outdated.
    /// @param value The value that is retrieved from the feed data.
    /// @param timestamp The time at which the value was last updated.
    /// @param max The maximum limit of the value.
    /// @param min The minimum limit of the value.
    /// @param heartbeat The maximum allowed time difference between
    ///                  current time and 'timestamp'.
    /// @return A boolean indicating whether the feed data had an error
    ///         (true = error, false = no error).
    function _verifyData(
        uint256 value,
        uint256 timestamp,
        uint256 max,
        uint256 min,
        uint256 heartbeat
    ) internal view returns (bool) {
        // Validate `value` is not below the buffered min value allowed.
        if (value < min) {
            return true;
        }

        // Validate `value` is not above the buffered maximum value allowed.
        if (value > max) {
            return true;
        }

        // Validate the price returned is not stale.
        if (block.timestamp - timestamp > heartbeat) {
            return true;
        }

        return false;
    }
}
