// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { BaseOracleAdaptor } from "contracts/oracles/adaptors/BaseOracleAdaptor.sol";
import { WAD } from "contracts/libraries/Constants.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IPriceRouter } from "contracts/interfaces/IPriceRouter.sol";
import { PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";
import { IChainlink } from "contracts/interfaces/external/chainlink/IChainlink.sol";

contract ChainlinkAdaptor is BaseOracleAdaptor {
    /// TYPES ///

    /// @notice Stores configuration data for Chainlink price sources.
    struct AdaptorData {
        /// @notice The current phase's aggregator address.
        IChainlink aggregator;
        /// @notice Whether the asset is configured or not.
        /// @dev    false = unconfigured; true = configured
        bool isConfigured;
        /// @notice Returns the number of decimals the aggregator responses with.
        uint8 decimals;
        /// @notice heartbeat the max amount of time between price updates
        /// @dev    0 defaults to using DEFAULT_HEART_BEAT
        uint256 heartbeat;
        /// @notice max the max valid price of the asset
        /// @dev    0 defaults to use aggregators max price reduced by ~10%
        uint256 max;
        /// @notice min the min valid price of the asset
        /// @dev    0 defaults to use aggregators min price increased by ~10%
        uint256 min;
    }

    /// CONSTANTS ///

    /// @notice If zero is specified for a Chainlink asset heartbeat,
    ///         this value is used instead.
    uint256 public constant DEFAULT_HEART_BEAT = 1 days;

    /// STORAGE ///

    /// @notice Chainlink Adaptor Data for pricing in ETH
    mapping(address => AdaptorData) public adaptorDataNonUSD;

    /// @notice Chainlink Adaptor Data for pricing in USD
    mapping(address => AdaptorData) public adaptorDataUSD;

    /// EVENTS ///

    event ChainlinkAssetAdded(address asset, AdaptorData assetConfig);
    event ChainlinkAssetRemoved(address asset);

    /// ERRORS ///

    error ChainlinkAdaptor__AssetIsNotSupported();
    error ChainlinkAdaptor__InvalidHeartbeat();
    error ChainlinkAdaptor__InvalidMinPrice();
    error ChainlinkAdaptor__InvalidMaxPrice();
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
    /// @return PriceReturnData A structure containing the price, error status,
    ///                         and the quote format of the price.
    function getPrice(
        address asset,
        bool inUSD,
        bool
    ) external view override returns (PriceReturnData memory) {
        if (!isSupportedAsset[asset]) {
            revert ChainlinkAdaptor__AssetIsNotSupported();
        }

        if (inUSD) {
            return _getPriceinUSD(asset);
        }

        return _getPriceinETH(asset);
    }

    /// @notice Add a Chainlink Price Feed as an asset.
    /// @dev Should be called before `PriceRouter:addAssetPriceFeed` is called.
    /// @param asset The address of the token to add pricing for
    /// @param aggregator Chainlink aggregator to use for pricing `asset`
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

        uint256 maxFromChainlink = uint256(
            uint192(feedAggregator.maxAnswer())
        );
        uint256 minFromChainklink = uint256(
            uint192(feedAggregator.minAnswer())
        );

        // Add a ~10% buffer to minimum and maximum price from Chainlink
        // because Chainlink can stop updating its price before/above
        // the min/max price.
        uint256 bufferedMaxPrice = (maxFromChainlink * 0.9e18) / WAD;
        uint256 bufferedMinPrice = (minFromChainklink * 1.1e18) / WAD;

        AdaptorData storage adaptorData;

        if (inUSD) {
            adaptorData = adaptorDataUSD[asset];
        } else {
            adaptorData = adaptorDataNonUSD[asset];
        }

        if (adaptorData.min == 0) {
            adaptorData.min = bufferedMinPrice;
        } else {
            if (adaptorData.min < bufferedMinPrice) {
                revert ChainlinkAdaptor__InvalidMinPrice();
            }
            adaptorData.min = bufferedMinPrice;
        }

        if (adaptorData.max == 0) {
            adaptorData.max = bufferedMaxPrice;
        } else {
            if (adaptorData.max > bufferedMaxPrice) {
                revert ChainlinkAdaptor__InvalidMaxPrice();
            }
            adaptorData.max = bufferedMaxPrice;
        }

        if ((bufferedMinPrice >= bufferedMaxPrice))
            revert ChainlinkAdaptor__InvalidMinMaxConfig();

        adaptorData.decimals = feedAggregator.decimals();
        adaptorData.heartbeat = heartbeat != 0
            ? heartbeat
            : DEFAULT_HEART_BEAT;

        adaptorData.aggregator = IChainlink(aggregator);
        adaptorData.isConfigured = true;
        isSupportedAsset[asset] = true;
        emit ChainlinkAssetAdded(asset, adaptorData);
    }

    /// @notice Removes a supported asset from the adaptor.
    /// @dev Calls back into price router to notify it of its removal
    function removeAsset(address asset) external override {
        _checkElevatedPermissions();

        if (!isSupportedAsset[asset]) {
            revert ChainlinkAdaptor__AssetIsNotSupported();
        }

        // Notify the adaptor to stop supporting the asset
        delete isSupportedAsset[asset];

        // Wipe config mapping entries for a gas refund
        delete adaptorDataUSD[asset];
        delete adaptorDataNonUSD[asset];

        // Notify the price router that we are going to stop supporting the asset
        IPriceRouter(centralRegistry.priceRouter()).notifyFeedRemoval(asset);
        emit ChainlinkAssetRemoved(asset);
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Retrieves the price of a given asset in USD.
    /// @param asset The address of the asset for which the price is needed.
    /// @return A structure containing the price, error status,
    ///         and the quote format of the price (USD).
    function _getPriceinUSD(
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
    function _getPriceinETH(
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
    /// @return A structure containing the price, error status,
    ///         and the currency of the price.
    function _parseData(
        AdaptorData memory data,
        bool inUSD
    ) internal view returns (PriceReturnData memory) {
        if (!IPriceRouter(centralRegistry.priceRouter()).isSequencerValid()) {
            return PriceReturnData({ price: 0, hadError: true, inUSD: inUSD });
        }

        (, int256 price, , uint256 updatedAt, ) = IChainlink(data.aggregator)
            .latestRoundData();
        uint256 newPrice = (uint256(price) * WAD) / (10 ** data.decimals);

        return (
            PriceReturnData({
                price: uint240(newPrice),
                hadError: _verifyData(
                    uint256(price),
                    updatedAt,
                    data.max,
                    data.min,
                    data.heartbeat
                ),
                inUSD: inUSD
            })
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
        if (value < min) {
            return true;
        }

        if (value > max) {
            return true;
        }

        if (block.timestamp - timestamp > heartbeat) {
            return true;
        }

        return false;
    }
}
