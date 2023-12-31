// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "contracts/libraries/redstone/PrimaryProdDataServiceConsumerBase.sol";

import { BaseOracleAdaptor } from "contracts/oracles/adaptors/BaseOracleAdaptor.sol";
import { IPriceRouter } from "contracts/interfaces/IPriceRouter.sol";
import { PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract EthereumRedstoneCoreAdaptor is PrimaryProdDataServiceConsumerBase, BaseOracleAdaptor {
    /// TYPES ///

    /// @notice Stores configuration data for Redstone price sources.
    /// @param heartbeat the max amount of time between price updates
    ///                  - 0 defaults to using DEFAULT_HEART_BEAT
    /// @param max the max valid price of the asset
    ///            - 0 defaults to use aggregators max price buffered by ~10%
    /// @param min the min valid price of the asset
    ///            - 0 defaults to use aggregators min price buffered by ~10%
    struct FeedData {
        bool isConfigured;
        uint256 heartbeat;
        uint256 max;
        uint256 min;
    }

    /// STORAGE ///

    /// @notice Redstone adaptor storage
    mapping(address => FeedData) public adaptorData;

    /// ERRORS ///

    error RedstoneAdaptor__AssetIsNotSupported();

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_
    ) BaseOracleAdaptor(centralRegistry_) {}

    /// EXTERNAL FUNCTIONS ///

    /// @notice Retrieves the price of a given asset.
    /// @dev Uses Redstone oracles to fetch the price data. Price is returned
    ///      in USD or ETH depending on 'inUSD' parameter.
    /// @param asset The address of the asset for which the price is needed.
    /// @param inUSD A boolean to determine if the price should be returned
    ///              in USD or not.
    /// @return PriceReturnData A structure containing the price, error status,
    ///         and the quote format of the price.
    function getPrice(
        address asset,
        bool inUSD,
        bool
    ) external view override returns (PriceReturnData memory) {
        if (!isSupportedAsset[asset]) {
            revert RedstoneAdaptor__AssetIsNotSupported();
        }
    }

    /// @notice Add a Redstone Price Feed as an asset.
    /// @dev Should be called before `PriceRouter:addAssetPriceFeed` is called.
    /// @param asset The address of the token to add pricing for
    /// @param aggregator Redstone aggregator to use for pricing `asset`
    /// @param inUSD Whether the price feed is in USD (inUSD = true)
    ///              or ETH (inUSD = false)
    function addAsset(
        address asset,
        address aggregator,
        bool inUSD
    ) external {
        _checkElevatedPermissions();
        isSupportedAsset[asset] = true;
    }

    /// @notice Removes a supported asset from the adaptor.
    /// @dev Calls back into price router to notify it of its removal
    function removeAsset(address asset) external override {
        _checkElevatedPermissions();
 
        if (!isSupportedAsset[asset]) {
            revert RedstoneAdaptor__AssetIsNotSupported();
        }

        // Notify the adaptor to stop supporting the asset
        delete isSupportedAsset[asset];

        // Wipe config mapping entries for a gas refund
        delete adaptorData[asset];

        // Notify the price router that we are going to stop supporting the asset
        IPriceRouter(centralRegistry.priceRouter()).notifyFeedRemoval(asset);
    }

    /// PUBLIC FUNCTIONS ///

    // This can be modified to increase/decrease required signers, max 4.
    function getUniqueSignersThreshold() public pure override returns (uint8) {
        return 3;
    }

}
