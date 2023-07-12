// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import { IChainlinkAggregator } from "contracts/interfaces/external/chainlink/IChainlinkAggregator.sol";

import { BaseOracleAdaptor } from "../BaseOracleAdaptor.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IPriceRouter } from "contracts/interfaces/IPriceRouter.sol";
import { IOracleAdaptor, PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";

contract ChainlinkAdaptor is BaseOracleAdaptor {

    /**
     * @notice Stores configuration data for Chainlink price sources.
     * @param max the max valid price of the asset
     *        - 0 defaults to use aggregators max price buffered by ~10%
     * @param min the min valid price of the asset
     *        - 0 defaults to use aggregators min price buffered by ~10%
     * @param heartbeat the max amount of time between price updates
     *        - 0 defaults to using DEFAULT_HEART_BEAT
     * @param inUsd bool indicating whether the price feed is
     *        denominated in USD(true) or ETH(false)
     */
    struct feedData {
        IChainlinkAggregator aggregator;
        bool isConfigured;//heartbeat will never be 64 bits so we can use some space for a bool to check instead of against aggregator != address(0)
        uint64 heartbeat;
        uint256 max;
        uint256 min;
    }

    /**
     * @notice If zero is specified for a Chainlink asset heartbeat, this value is used instead.
     */
    uint24 public constant DEFAULT_HEART_BEAT = 1 days;

    /// @notice Chainlink Stable Pool Adaptor Storage
    mapping(address => feedData) public adaptorDataNonUSD;

    /// @notice Chainlink Stable Pool Adaptor Storage
    mapping(address => feedData) public adaptorDataUSD;

        constructor(ICentralRegistry _centralRegistry) BaseOracleAdaptor(_centralRegistry) {}


    /// @notice Called by PriceRouter to price an asset.
    function getPrice(
        address _asset,
        bool _isUsd,
        bool _getLower
    ) external view override returns (PriceReturnData memory) {
        PriceReturnData memory data = PriceReturnData({
            price: 0,
            hadError: false,
            inUSD: false
        });
        return data;
    }

    /**
     * @notice Add a Chainlink Price Feed as an asset.
     * @dev Should be called before `PriceRouter:addAssetPriceFeed` is called.
     * @param _asset The address of the token to add pricing for
     * @param _aggregator Chainlink aggregator to use for pricing `_asset`
     * @param _inUSD Whether the price feed is in USD (_inUSD = true) or ETH (_inUSD = false)
     */
    function addAsset(
        address _asset,
        address _aggregator,
        bool _inUSD
    ) external onlyDaoManager {

        // Use Chainlink to get the min and max of the asset.
        IChainlinkAggregator aggregator = IChainlinkAggregator(
            IChainlinkAggregator(_aggregator).aggregator()
        );
        uint256 maxFromChainlink = uint256(uint192(aggregator.maxAnswer()));
        uint256 minFromChainklink = uint256(uint192(aggregator.minAnswer()));
        
        // Add a ~10% buffer to minimum and maximum price from Chainlink because Chainlink can stop updating
        // its price before/above the min/max price.
        uint256 bufferedMaxPrice = (maxFromChainlink * 0.9e18) / 1e18;
        uint256 bufferedMinPrice = (minFromChainklink * 1.1e18) / 1e18;
        

        feedData storage _feedData;

        if (_inUSD) {
            _feedData = adaptorDataUSD[_asset];
        } else {
            _feedData = adaptorDataNonUSD[_asset];
        }

        if (_feedData.min == 0) {
        } else {
            require(_feedData.min >= bufferedMinPrice, "ChainlinkAdaptor: invalid min price");
        }

        if (_feedData.max == 0) {
        } else {
            require(_feedData.max <= bufferedMaxPrice, "ChainlinkAdaptor: invalid max price");
        }

        require(_feedData.min < _feedData.max, "ChainlinkAdaptor: invalid min/max config");

        _feedData.heartbeat = _feedData.heartbeat != 0
            ? _feedData.heartbeat
            : DEFAULT_HEART_BEAT;

        _feedData.aggregator = IChainlinkAggregator(_aggregator);
        _feedData.isConfigured = true;
        isSupportedAsset[_asset] = true;

    }

    /// @notice Removes a supported asset from the adaptor.
    /// @dev Calls back into price router to notify it of its removal
    function removeAsset(address _asset) external override onlyDaoManager {
        require(
            isSupportedAsset[_asset],
            "ChainlinkAdaptor: asset not supported"
        );

        /// Notify the adaptor to stop supporting the asset 
        delete isSupportedAsset[_asset];

        /// Wipe config mapping entries for a gas refund
        delete adaptorDataUSD[_asset];
        delete adaptorDataNonUSD[_asset];

        /// Notify the price router that we are going to stop supporting the asset 
        IPriceRouter(centralRegistry.priceRouter()).notifyAssetPriceFeedRemoval(_asset);
    }
}
