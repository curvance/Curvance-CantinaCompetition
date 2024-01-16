// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CurveBaseAdaptor } from "contracts/oracles/adaptors/curve/CurveBaseAdaptor.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";
import { IPriceRouter } from "contracts/interfaces/IPriceRouter.sol";
import { ICurvePool } from "contracts/interfaces/external/curve/ICurvePool.sol";

contract Curve2PoolAdapter is CurveBaseAdaptor {
    /// TYPES ///

    struct AdaptorData {
        address pool;
        address underlyingOrConstituent0;
        address underlyingOrConstituent1;
        bool divideRate0; // If we only have the market price of the underlying, and there is a rate with the underlying, then divide out the rate
        bool divideRate1; // If we only new the safe price of sDAI, then we need to divide out the rate stored in the curve pool
        bool isCorrelated; // but if we know the safe market price of DAI then we can just use that.
        uint32 upperBound; // decimals 4
        uint32 lowerBound; // decimals 4
    }

    /// STORAGE ///

    /// @notice Curve Pool Adaptor Storage
    mapping(address => AdaptorData) public adaptorData;

    /// EVENTS ///

    event CurvePoolAssetAdded(address asset, AdaptorData assetConfig);

    event CurvePoolAssetRemoved(address asset);

    /// ERRORS ///

    error Curve2PoolAdapter__UnsupportedPool();
    error Curve2PoolAdapter__DidNotConverge();
    error Curve2PoolAdapter__Reentrant();
    error Curve2PoolAdapter__AssetIsAlreadyAdded();
    error Curve2PoolAdapter__AssetIsNotSupported();
    error Curve2PoolAdapter__QuoteAssetIsNotSupported();
    error Curve2PoolAdapter_Bounds_Exeeded();

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_
    ) CurveBaseAdaptor(centralRegistry_) {}

    /// EXTERNAL FUNCTIONS ///

    /// @notice Sets or updates a Curve pool configuration for the reentrancy check
    /// @param coinsLength The number of coins (from .coinsLength) on the Curve pool
    /// @param gasLimit The gas limit to be set on the check
    function setReentrancyConfig(
        uint256 coinsLength,
        uint256 gasLimit
    ) external {
        _checkElevatedPermissions();
        _setReentrancyConfig(coinsLength, gasLimit);
    }

    /// @notice Retrieves the price of a given asset.
    /// @dev Uses Curve to fetch the price data for the LP token.
    ///      Price is returned in USD or ETH depending on 'inUSD' parameter.
    /// @param asset The address of the asset for which the price is needed.
    /// @param inUSD A boolean to determine if the price should be returned in
    ///              USD or not.
    /// @param getLower A boolean to determine if lower of two oracle prices
    ///                 should be retrieved.
    /// @return pData A structure containing the price, error status,
    ///                         and the quote format of the price.
    function getPrice(
        address asset,
        bool inUSD,
        bool getLower
    ) external view override returns (PriceReturnData memory pData) {
        pData.inUSD = inUSD;

        if (isLocked(asset, 2)) {
            revert Curve2PoolAdapter__Reentrant();
        }

        AdaptorData memory adapter = adaptorData[asset];
        ICurvePool pool = ICurvePool(adapter.pool);

        // Make sure virtualPrice is reasonable.
        uint256 virtualPrice = pool.get_virtual_price();
        _enforceBounds(virtualPrice, adapter.lowerBound, adapter.upperBound);

        // Get underlying token prices
        IPriceRouter priceRouter = IPriceRouter(centralRegistry.priceRouter());
        uint256 price0;
        uint256 price1;
        uint256 errorCode;
        (price0, errorCode) = priceRouter.getPrice(
            adapter.underlyingOrConstituent0,
            inUSD,
            getLower
        );
        if (errorCode > 0) {
            pData.hadError = true;
            return pData;
        }
        (price1, errorCode) = priceRouter.getPrice(
            adapter.underlyingOrConstituent1,
            inUSD,
            getLower
        );
        if (errorCode > 0) {
            pData.hadError = true;
            return pData;
        }

        // Calculate LP token price
        uint256 price;
        if (adapter.isCorrelated) {
            // Handle rates if needed.
            if (adapter.divideRate0 || adapter.divideRate1) {
                uint256[2] memory rates = pool.stored_rates();
                if (adapter.divideRate0) {
                    price0 = (price0 * 1e18) / rates[0];
                }
                if (adapter.divideRate1) {
                    price1 = (price1 * 1e18) / rates[1];
                }
            }

            if (getLower) {
                // Find the minimum price of coins.
                uint256 minPrice = price0 < price1 ? price0 : price1;
                price = (minPrice * virtualPrice) / 1e18;
            } else {
                // Find the maximum price of coins.
                uint256 maxPrice = price0 < price1 ? price1 : price0;
                price = (maxPrice * virtualPrice) / 1e18;
            }
        } else {
            price = (2 * virtualPrice * _sqrt(price0)) / _sqrt(price1);
            price = (price * price0) / 1e18;
        }

        pData.price = uint240(price);
    }

    /// @notice Adds a Curve LP as an asset.
    /// @dev Should be called before `PriceRouter:addAssetPriceFeed` is called.
    /// @param asset the address of the lp to add
    function addAsset(address asset, AdaptorData memory data) external {
        _checkElevatedPermissions();

        if (isSupportedAsset[asset]) {
            revert Curve2PoolAdapter__AssetIsAlreadyAdded();
        }

        // Make sure that the asset being added has the proper input
        // via this sanity check
        if (isLocked(asset, 2)) {
            revert Curve2PoolAdapter__UnsupportedPool();
        }

        if (
            !IPriceRouter(centralRegistry.priceRouter()).isSupportedAsset(
                data.underlyingOrConstituent0
            )
        ) {
            revert Curve2PoolAdapter__QuoteAssetIsNotSupported();
        }

        if (
            !IPriceRouter(centralRegistry.priceRouter()).isSupportedAsset(
                data.underlyingOrConstituent1
            )
        ) {
            revert Curve2PoolAdapter__QuoteAssetIsNotSupported();
        }

        adaptorData[asset] = data;

        // Notify the adaptor to support the asset
        isSupportedAsset[asset] = true;
        emit CurvePoolAssetAdded(asset, data);
    }

    /// @notice Removes a supported asset from the adaptor.
    /// @dev Calls back into price router to notify it of its removal
    function removeAsset(address asset) external override {
        _checkElevatedPermissions();

        if (!isSupportedAsset[asset]) {
            revert Curve2PoolAdapter__AssetIsNotSupported();
        }

        // Notify the adaptor to stop supporting the asset
        delete isSupportedAsset[asset];
        // Wipe config mapping entries for a gas refund
        delete adaptorData[asset];

        // Notify the price router that we are going to stop supporting the asset
        IPriceRouter(centralRegistry.priceRouter()).notifyFeedRemoval(asset);
        emit CurvePoolAssetRemoved(asset);
    }

    /**
     * @notice Calculates the square root of the input.
     */
    function _sqrt(uint256 _x) internal pure returns (uint256 y) {
        uint256 z = (_x + 1) / 2;
        y = _x;
        while (z < y) {
            y = z;
            z = (_x / z + z) / 2;
        }
    }

    /**
     * @notice Helper function to check if a provided answer is within a reasonable bound.
     */
    function _enforceBounds(
        uint256 providedAnswer, // decimals 18
        uint32 lowerBound, // decimals 4
        uint32 upperBound // decimals 4
    ) internal view {
        uint32 providedAnswerConvertedToBoundDecimals = uint32(
            providedAnswer / 1e14
        );
        if (
            providedAnswerConvertedToBoundDecimals < lowerBound ||
            providedAnswerConvertedToBoundDecimals > upperBound
        ) revert Curve2PoolAdapter_Bounds_Exeeded();
    }
}
