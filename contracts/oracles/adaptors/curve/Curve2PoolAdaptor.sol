// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CurveBaseAdaptor } from "contracts/oracles/adaptors/curve/CurveBaseAdaptor.sol";
import { WAD } from "contracts/libraries/Constants.sol";
import { FixedPointMathLib } from "contracts/libraries/external/FixedPointMathLib.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";
import { IPriceRouter } from "contracts/interfaces/IPriceRouter.sol";
import { ICurvePool } from "contracts/interfaces/external/curve/ICurvePool.sol";

contract Curve2PoolAdaptor is CurveBaseAdaptor {
    /// TYPES ///

    struct AdaptorData {
        address pool;
        address underlyingOrConstituent0;
        address underlyingOrConstituent1;
        /// @notice If we only have the market price of the underlying, 
        ///         and there is a rate with the underlying, 
        ///         then divide out the rate.
        bool divideRate0; // 
        /// @notice If we only new the safe price of constitient assets like sDAI,
        ///         then we need to divide out the rate stored in the curve pool.
        bool divideRate1;
        bool isCorrelated;
        uint256 upperBound;
        uint256 lowerBound;
    }

    /// CONSTANTS ///

    /// @notice Maximum bound range that can be increased on either side, 
    ///         this is not meant to be anti tamperproof but,
    ///         more-so mitigate any human error.
    uint256 internal constant _MAX_BOUND_INCREASE = .02e18;

    /// STORAGE ///

    /// @notice Curve Pool Adaptor Storage.
    mapping(address => AdaptorData) public adaptorData;

    /// EVENTS ///

    event CurvePoolAssetAdded(address asset, AdaptorData assetConfig);
    event CurvePoolAssetRemoved(address asset);

    /// ERRORS ///

    error Curve2PoolAdaptor__UnsupportedPool();
    error Curve2PoolAdaptor__DidNotConverge();
    error Curve2PoolAdaptor__Reentrant();
    error Curve2PoolAdaptor__AssetIsAlreadyAdded();
    error Curve2PoolAdaptor__AssetIsNotSupported();
    error Curve2PoolAdaptor__QuoteAssetIsNotSupported();
    error Curve2PoolAdaptor__InvalidBounds();
    error Curve2PoolAdaptor__BoundsExceeded();

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_
    ) CurveBaseAdaptor(centralRegistry_) {}

    /// EXTERNAL FUNCTIONS ///

    /// @notice Sets or updates a Curve pool configuration for the reentrancy check.
    /// @param coinsLength The number of coins (from .coinsLength) on the Curve pool.
    /// @param gasLimit The gas limit to be set on the check.
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
            revert Curve2PoolAdaptor__Reentrant();
        }

        AdaptorData memory Adaptor = adaptorData[asset];
        ICurvePool pool = ICurvePool(Adaptor.pool);

        // Make sure virtualPrice is reasonable.
        uint256 virtualPrice = pool.get_virtual_price();
        _enforceBounds(virtualPrice, Adaptor.lowerBound, Adaptor.upperBound);

        // Get underlying token prices.
        IPriceRouter priceRouter = IPriceRouter(centralRegistry.priceRouter());
        uint256 price0;
        uint256 price1;
        uint256 errorCode;
        (price0, errorCode) = priceRouter.getPrice(
            Adaptor.underlyingOrConstituent0,
            inUSD,
            getLower
        );
        if (errorCode > 0) {
            pData.hadError = true;
            return pData;
        }
        (price1, errorCode) = priceRouter.getPrice(
            Adaptor.underlyingOrConstituent1,
            inUSD,
            getLower
        );
        if (errorCode > 0) {
            pData.hadError = true;
            return pData;
        }

        // Calculate LP token price.
        uint256 price;
        if (Adaptor.isCorrelated) {
            // Handle rates if needed.
            if (Adaptor.divideRate0 || Adaptor.divideRate1) {
                uint256[2] memory rates = pool.stored_rates();
                if (Adaptor.divideRate0) {
                    price0 = (price0 * WAD) / rates[0];
                }
                if (Adaptor.divideRate1) {
                    price1 = (price1 * WAD) / rates[1];
                }
            }

            if (getLower) {
                // Find the minimum price of coins.
                uint256 minPrice = price0 < price1 ? price0 : price1;
                price = (minPrice * virtualPrice) / WAD;
            } else {
                // Find the maximum price of coins.
                uint256 maxPrice = price0 < price1 ? price1 : price0;
                price = (maxPrice * virtualPrice) / WAD;
            }
        } else {
            price = (2 * virtualPrice * FixedPointMathLib.sqrt(price0)) / FixedPointMathLib.sqrt(price1);
            price = (price * price0) / WAD;
        }

        pData.price = uint240(price);
    }

    /// @notice Adds a Curve LP as an asset.
    /// @dev Should be called before `PriceRouter:addAssetPriceFeed` is called.
    /// @param asset the address of the lp to add
    function addAsset(address asset, AdaptorData memory data) external {
        _checkElevatedPermissions();

        if (isSupportedAsset[asset]) {
            revert Curve2PoolAdaptor__AssetIsAlreadyAdded();
        }

        // Make sure that the asset being added has the proper input
        // via this sanity check
        if (isLocked(asset, 2)) {
            revert Curve2PoolAdaptor__UnsupportedPool();
        }

        if (
            !IPriceRouter(centralRegistry.priceRouter()).isSupportedAsset(
                data.underlyingOrConstituent0
            )
        ) {
            revert Curve2PoolAdaptor__QuoteAssetIsNotSupported();
        }

        if (
            !IPriceRouter(centralRegistry.priceRouter()).isSupportedAsset(
                data.underlyingOrConstituent1
            )
        ) {
            revert Curve2PoolAdaptor__QuoteAssetIsNotSupported();
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
            revert Curve2PoolAdaptor__AssetIsNotSupported();
        }

        // Notify the adaptor to stop supporting the asset
        delete isSupportedAsset[asset];
        // Wipe config mapping entries for a gas refund
        delete adaptorData[asset];

        // Notify the price router that we are going to stop supporting the asset
        IPriceRouter(centralRegistry.priceRouter()).notifyFeedRemoval(asset);
        emit CurvePoolAssetRemoved(asset);
    }

    function raiseBounds(
        address asset,
        uint256 newLowerBound, 
        uint256 newUpperBound
    ) external {
        _checkElevatedPermissions();

        // Convert the parameters from `basis points` to `WAD` form,
        // while inefficient consistently entering parameters in basis points
        // minimizes potential human error, 
        // even if it costs a bit extra gas on configuration.
        newLowerBound = _bpToWad(newLowerBound);
        newUpperBound = _bpToWad(newUpperBound);

        AdaptorData storage adaptorData = adaptorData[asset];
        uint256 oldLowerBound = adaptorData.lowerBound;
        uint256 oldUpperBound = adaptorData.upperBound;

        // Validate that the new bounds are higher than the old ones, 
        // since virtual prices only rise overtime, 
        // so they should never be decreased here.
        if (
            newLowerBound <= oldLowerBound || 
            newUpperBound <= oldUpperBound
        ) {
            revert Curve2PoolAdaptor__InvalidBounds();
        }

        if (oldLowerBound + _MAX_BOUND_INCREASE < newLowerBound) {
            revert Curve2PoolAdaptor__InvalidBounds();
        }

        if (oldUpperBound + _MAX_BOUND_INCREASE < newUpperBound) {
            revert Curve2PoolAdaptor__InvalidBounds();
        }

        adaptorData.lowerBound = newLowerBound;
        adaptorData.upperBound = newUpperBound;
    }

    /// @notice Checks if `price` is within a reasonable bound.
    function _enforceBounds(
        uint256 price,
        uint256 lowerBound,
        uint256 upperBound
    ) internal view {
        if (price < lowerBound || price > upperBound) {
            revert Curve2PoolAdaptor__BoundsExceeded();
        }
    }

    /// @dev Internal helper function for easily converting between scalars
    function _bpToWad(uint256 value) internal pure returns (uint256) {
        // multiplies by 1e14 to convert from basis points to WAD
        return value * 100000000000000;
    }
}
