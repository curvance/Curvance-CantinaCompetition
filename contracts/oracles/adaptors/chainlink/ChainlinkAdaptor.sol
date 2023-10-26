// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { BaseOracleAdaptor } from "contracts/oracles/adaptors/BaseOracleAdaptor.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IPriceRouter } from "contracts/interfaces/IPriceRouter.sol";
import { PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";
import { IChainlink } from "contracts/interfaces/external/chainlink/IChainlink.sol";

contract ChainlinkAdaptor is BaseOracleAdaptor {
    /// TYPES ///

    /// @notice Stores configuration data for Chainlink price sources.
    struct FeedData {
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

    /// @notice Time to pass before accepting answers when sequencer
    ///         comes back up.
    uint256 public constant GRACE_PERIOD_TIME = 3600;

    /// @notice If zero is specified for a Chainlink asset heartbeat,
    ///         this value is used instead.
    uint24 public constant DEFAULT_HEART_BEAT = 1 days;

    /// STORAGE ///

    /// @notice Chainlink Adaptor Data for pricing in ETH
    mapping(address => FeedData) public adaptorDataNonUSD;

    /// @notice Chainlink Adaptor Data for pricing in USD
    mapping(address => FeedData) public adaptorDataUSD;

    /// ERRORS ///

    error ChainlinkAdaptor__AssetIsNotSupported();
    error ChainlinkAdaptor__InvalidMinPrice();
    error ChainlinkAdaptor__InvalidMaxPrice();
    error ChainlinkAdaptor__InvalidMinMaxConfig();
    error ChainlinkAdaptor__SequencerIsDown();
    error ChainlinkAdaptor__GracePeriodNotOver();

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
    /// @param inUSD Whether the price feed is in USD (inUSD = true)
    ///              or ETH (inUSD = false)
    function addAsset(
        address asset,
        address aggregator,
        bool inUSD
    ) external onlyElevatedPermissions {
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
            if (feedData.min < bufferedMinPrice) {
                revert ChainlinkAdaptor__InvalidMinPrice();
            }
            feedData.min = bufferedMinPrice;
        }

        if (feedData.max == 0) {
            feedData.max = bufferedMaxPrice;
        } else {
            if (feedData.max > bufferedMaxPrice) {
                revert ChainlinkAdaptor__InvalidMaxPrice();
            }
            feedData.max = bufferedMaxPrice;
        }

        if (minFromChainklink >= maxFromChainlink)
            revert ChainlinkAdaptor__InvalidMinMaxConfig();

        feedData.decimals = feedAggregator.decimals();
        feedData.heartbeat = feedData.heartbeat != 0
            ? feedData.heartbeat
            : DEFAULT_HEART_BEAT;

        feedData.aggregator = IChainlink(aggregator);
        feedData.isConfigured = true;
        isSupportedAsset[asset] = true;
    }

    /// @notice Removes a supported asset from the adaptor.
    /// @dev Calls back into price router to notify it of its removal
    function removeAsset(address asset) external override onlyDaoPermissions {
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
            return _parseFeedData(adaptorDataUSD[asset], true);
        }

        return _parseFeedData(adaptorDataNonUSD[asset], false);
    }

    /// @notice Retrieves the price of a given asset in ETH.
    /// @param asset The address of the asset for which the price is needed.
    /// @return A structure containing the price, error status,
    ///         and the quote format of the price (ETH).
    function _getPriceinETH(
        address asset
    ) internal view returns (PriceReturnData memory) {
        if (adaptorDataNonUSD[asset].isConfigured) {
            return _parseFeedData(adaptorDataNonUSD[asset], false);
        }

        return _parseFeedData(adaptorDataUSD[asset], true);
    }

    /// @notice Parses the chainlink feed data for pricing of an asset.
    /// @dev Calls latestRoundData() from Chainlink to get the latest data
    ///      for pricing and staleness.
    /// @param feed Chainlink feed details.
    /// @param inUSD A boolean to denote if the price is in USD.
    /// @return A structure containing the price, error status,
    ///         and the currency of the price.
    function _parseFeedData(
        FeedData memory feed,
        bool inUSD
    ) internal view returns (PriceReturnData memory) {
        address sequencer = centralRegistry.sequencer();

        if (sequencer != address(0)) {
            (, int256 answer, uint256 startedAt, , ) = IChainlink(sequencer)
                .latestRoundData();

            // Answer == 0: Sequencer is up
            // Check that the sequencer is up.
            if (answer != 0) {
                revert ChainlinkAdaptor__SequencerIsDown();
            }

            // Check that the grace period has passed after the
            // sequencer is back up.
            if (block.timestamp < startedAt + GRACE_PERIOD_TIME) {
                revert ChainlinkAdaptor__GracePeriodNotOver();
            }
        }

        (, int256 price, , uint256 updatedAt, ) = IChainlink(feed.aggregator)
            .latestRoundData();
        uint256 newPrice = (uint256(price) * 1e18) / (10 ** feed.decimals);

        return (
            PriceReturnData({
                price: uint240(newPrice),
                hadError: _validateFeedData(
                    uint256(price),
                    updatedAt,
                    feed.max,
                    feed.min,
                    feed.heartbeat
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
}
