// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { BaseOracleAdaptor } from "contracts/oracles/adaptors/BaseOracleAdaptor.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IPriceRouter } from "contracts/interfaces/IPriceRouter.sol";
import { IOracleAdaptor, PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";
import { IChainlinkAggregator } from "contracts/interfaces/external/chainlink/IChainlinkAggregator.sol";

contract ChainlinkAdaptor is BaseOracleAdaptor {
    /// @notice Stores configuration data for Chainlink price sources.
    /// @param heartbeat the max amount of time between price updates
    ///        - 0 defaults to using DEFAULT_HEART_BEAT
    /// @param max the max valid price of the asset
    ///        - 0 defaults to use aggregators max price buffered by ~10%
    /// @param min the min valid price of the asset
    ///        - 0 defaults to use aggregators min price buffered by ~10%
    struct FeedData {
        IChainlinkAggregator aggregator;
        bool isConfigured;
        uint256 heartbeat;
        uint256 max;
        uint256 min;
    }

    /// @notice If zero is specified for a Chainlink asset heartbeat, this value is used instead.
    uint24 public constant DEFAULT_HEART_BEAT = 1 days;

    /// @notice Chainlink Adaptor Data for pricing in ETH
    mapping(address => FeedData) public adaptorDataNonUSD;

    /// @notice Chainlink Adaptor Data for pricing in USD
    mapping(address => FeedData) public adaptorDataUSD;

    constructor(
        ICentralRegistry centralRegistry_
    ) BaseOracleAdaptor(centralRegistry_) {}

    /// @notice Retrieves the price of a given asset.
    /// @dev Uses Chainlink oracles to fetch the price data. Price is returned in USD or ETH depending on 'isUsd' parameter.
    /// @param asset The address of the asset for which the price is needed.
    /// @param isUsd A boolean to determine if the price should be returned in USD or not.
    /// @return PriceReturnData A structure containing the price, error status, and the quote format of the price.
    function getPrice(
        address asset,
        bool isUsd,
        bool
    ) external view override returns (PriceReturnData memory) {
        require(
            isSupportedAsset[asset],
            "ChainlinkAdaptor: asset not supported"
        );

        if (isUsd) {
            return _getPriceinUSD(asset);
        }

        return _getPriceinETH(asset);
    }

    /// @notice Retrieves the price of a given asset in USD.
    /// @param asset The address of the asset for which the price is needed.
    /// @return A structure containing the price, error status, and the quote format of the price (USD).
    function _getPriceinUSD(
        address asset
    ) internal view returns (PriceReturnData memory) {
        if (adaptorDataUSD[asset].isConfigured) {
            return _parseFeedData(adaptorDataUSD[asset], true);
        }

        return _parseFeedData(adaptorDataNonUSD[asset], false);
    }

    /// @notice Retrieves the price of a given asset in ETH.
    /// @param asset The address of the asset for which the price is needed.
    /// @return A structure containing the price, error status, and the quote format of the price (ETH).
    function _getPriceinETH(
        address asset
    ) internal view returns (PriceReturnData memory) {
        if (adaptorDataNonUSD[asset].isConfigured) {
            return _parseFeedData(adaptorDataNonUSD[asset], false);
        }

        return _parseFeedData(adaptorDataUSD[asset], true);
    }

    /// @notice Parses the chainlink feed data for pricing of an asset.
    /// @dev Calls latestRoundData() from Chainlink to get the latest data for pricing and staleness.
    /// @param chainlinkFeed Chainlink feed details.
    /// @param inUSD A boolean to denote if the price is in USD.
    /// @return A structure containing the price, error status, and the currency of the price.
    function _parseFeedData(
        FeedData memory chainlinkFeed,
        bool inUSD
    ) internal view returns (PriceReturnData memory) {
        (, int256 feedPrice, , uint256 updatedAt, ) = IChainlinkAggregator(
            chainlinkFeed.aggregator
        ).latestRoundData();
        uint256 convertedPrice = uint256(feedPrice);

        return (
            PriceReturnData({
                price: uint240(convertedPrice),
                hadError: _validateFeedData(
                    convertedPrice,
                    updatedAt,
                    chainlinkFeed.max,
                    chainlinkFeed.min,
                    chainlinkFeed.heartbeat
                ),
                inUSD: inUSD
            })
        );
    }

    /// @notice Validates the feed data based on various constraints.
    /// @dev Checks if the value is within a specific range and if the data is not outdated.
    /// @param value The value that is retrieved from the feed data.
    /// @param timestamp The time at which the value was last updated.
    /// @param max The maximum limit of the value.
    /// @param min The minimum limit of the value.
    /// @param heartbeat The maximum allowed time difference between current time and 'timestamp'.
    /// @return A boolean indicating whether the feed data had an error (true = error, false = no error).
    function _validateFeedData(
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

    /// @notice Add a Chainlink Price Feed as an asset.
    /// @dev Should be called before `PriceRouter:addAssetPriceFeed` is called.
    /// @param asset The address of the token to add pricing for
    /// @param aggregator Chainlink aggregator to use for pricing `asset`
    /// @param inUSD Whether the price feed is in USD (inUSD = true) or ETH (inUSD = false)
    function addAsset(
        address asset,
        address aggregator,
        bool inUSD
    ) external onlyElevatedPermissions {
        // Use Chainlink to get the min and max of the asset.
        IChainlinkAggregator feedAggregator = IChainlinkAggregator(
            IChainlinkAggregator(aggregator).aggregator()
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
        uint256 bufferedMaxPrice = (maxFromChainlink * 0.9e18) / 1e18;
        uint256 bufferedMinPrice = (minFromChainklink * 1.1e18) / 1e18;

        FeedData storage feedData;

        if (inUSD) {
            feedData = adaptorDataUSD[asset];
        } else {
            feedData = adaptorDataNonUSD[asset];
        }

        if (feedData.min == 0) {
            feedData.min = bufferedMinPrice;
        } else {
            require(
                feedData.min >= bufferedMinPrice,
                "ChainlinkAdaptor: invalid min price"
            );
            feedData.min = bufferedMinPrice;
        }

        if (feedData.max == 0) {
            feedData.max = bufferedMaxPrice;
        } else {
            require(
                feedData.max <= bufferedMaxPrice,
                "ChainlinkAdaptor: invalid max price"
            );
            feedData.max = bufferedMaxPrice;
        }

        require(
            feedData.min < feedData.max,
            "ChainlinkAdaptor: invalid min/max config"
        );

        feedData.heartbeat = feedData.heartbeat != 0
            ? feedData.heartbeat
            : DEFAULT_HEART_BEAT;

        feedData.aggregator = IChainlinkAggregator(aggregator);
        feedData.isConfigured = true;
        isSupportedAsset[asset] = true;
    }

    /// @notice Removes a supported asset from the adaptor.
    /// @dev Calls back into price router to notify it of its removal
    function removeAsset(address asset) external override onlyDaoPermissions {
        require(
            isSupportedAsset[asset],
            "ChainlinkAdaptor: asset not supported"
        );

        /// Notify the adaptor to stop supporting the asset
        delete isSupportedAsset[asset];

        /// Wipe config mapping entries for a gas refund
        delete adaptorDataUSD[asset];
        delete adaptorDataNonUSD[asset];

        /// Notify the price router that we are going to stop supporting the asset
        IPriceRouter(centralRegistry.priceRouter())
            .notifyAssetPriceFeedRemoval(asset);
    }
}
