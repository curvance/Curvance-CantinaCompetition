// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CurveBaseAdaptor } from "contracts/oracles/adaptors/curve/CurveBaseAdaptor.sol";
import { WAD } from "contracts/libraries/Constants.sol";
import { FixedPointMathLib } from "contracts/libraries/external/FixedPointMathLib.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";
import { IOracleRouter } from "contracts/interfaces/IOracleRouter.sol";
import { ICurvePool } from "contracts/interfaces/external/curve/ICurvePool.sol";

contract Curve2PoolLPAdaptor is CurveBaseAdaptor {
    /// TYPES ///

    struct AdaptorData {
        address pool;
        address underlyingOrConstituent0;
        address underlyingOrConstituent1;
        /// @notice If we only have the market price of the underlying,
        ///         and there is a rate with the underlying,
        ///         then divide out the rate.
        bool divideRate0;
        /// @notice If we only new the safe price of constitient assets
        ///         like sDAI,then we need to divide out the rate stored
        ///         in the curve pool.
        bool divideRate1;
        bool isCorrelated;
        /// @notice Upper bound allowed for an LP token's virtual price.
        uint256 upperBound;
        /// @notice Lower bound allowed for an LP token's virtual price.
        uint256 lowerBound;
    }

    /// CONSTANTS ///

    /// @notice Maximum bound range that can be increased on either side,
    ///         this is not meant to be anti tamperproof but,
    ///         more-so mitigate any human error. 2%.
    uint256 internal constant _MAX_BOUND_INCREASE = .02e18;
    /// @notice Maximum difference between lower bound and upper bound,
    ///         checked on configuration. 5%.
    uint256 internal constant _MAX_BOUND_RANGE = .05e18;

    /// STORAGE ///

    /// @notice Curve Pool Adaptor Storage.
    mapping(address => AdaptorData) public adaptorData;

    /// EVENTS ///

    event CurvePoolAssetAdded(address asset, AdaptorData assetConfig);
    event CurvePoolAssetRemoved(address asset);

    /// ERRORS ///

    error Curve2PoolLPAdaptor__Reentrant();
    error Curve2PoolLPAdaptor__BoundsExceeded();
    error Curve2PoolLPAdaptor__UnsupportedPool();
    error Curve2PoolLPAdaptor__AssetIsAlreadyAdded();
    error Curve2PoolLPAdaptor__AssetIsNotSupported();
    error Curve2PoolLPAdaptor__QuoteAssetIsNotSupported();
    error Curve2PoolLPAdaptor__InvalidBounds();

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
            revert Curve2PoolLPAdaptor__Reentrant();
        }

        AdaptorData memory data = adaptorData[asset];
        ICurvePool pool = ICurvePool(data.pool);

        // Make sure virtualPrice is reasonable.
        uint256 virtualPrice = pool.get_virtual_price();
        _enforceBounds(virtualPrice, data.lowerBound, data.upperBound);

        // Get underlying token prices.
        IOracleRouter oracleRouter = IOracleRouter(centralRegistry.oracleRouter());
        uint256 price0;
        uint256 price1;
        uint256 errorCode;
        (price0, errorCode) = oracleRouter.getPrice(
            data.underlyingOrConstituent0,
            inUSD,
            getLower
        );
        if (errorCode > 0) {
            pData.hadError = true;
            return pData;
        }
        (price1, errorCode) = oracleRouter.getPrice(
            data.underlyingOrConstituent1,
            inUSD,
            getLower
        );
        if (errorCode > 0) {
            pData.hadError = true;
            return pData;
        }

        // Calculate LP token price.
        uint256 price;
        if (data.isCorrelated) {
            // Handle rates if needed.
            if (data.divideRate0 || data.divideRate1) {
                uint256[2] memory rates = pool.stored_rates();
                if (data.divideRate0) {
                    price0 = (price0 * WAD) / rates[0];
                }
                if (data.divideRate1) {
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
            price =
                (2 * virtualPrice * FixedPointMathLib.sqrt(price0)) /
                FixedPointMathLib.sqrt(price1);
            price = (price * price0) / WAD;
        }

        if (_checkOracleOverflow(price)) {
            pData.hadError = true;
            return pData;
        }

        pData.price = uint240(price);
    }

    /// @notice Adds a Curve LP as an asset.
    /// @dev Should be called before `OracleRouter:addAssetPriceFeed` is called.
    /// @param asset the address of the lp to add
    function addAsset(address asset, AdaptorData memory data) external {
        _checkElevatedPermissions();

        if (isSupportedAsset[asset]) {
            revert Curve2PoolLPAdaptor__AssetIsAlreadyAdded();
        }

        // Make sure that the asset being added has the proper input
        // via this sanity check.
        if (isLocked(asset, 2)) {
            revert Curve2PoolLPAdaptor__UnsupportedPool();
        }

        address oracleRouter = centralRegistry.oracleRouter();

        if (
            !IOracleRouter(oracleRouter).isSupportedAsset(
                data.underlyingOrConstituent0
            )
        ) {
            revert Curve2PoolLPAdaptor__QuoteAssetIsNotSupported();
        }

        if (
            !IOracleRouter(oracleRouter).isSupportedAsset(
                data.underlyingOrConstituent1
            )
        ) {
            revert Curve2PoolLPAdaptor__QuoteAssetIsNotSupported();
        }

        // Validate that the upper bound is greater than the lower bound.
        if (data.lowerBound >= data.upperBound) {
            revert Curve2PoolLPAdaptor__InvalidBounds();
        }

        ICurvePool pool = ICurvePool(data.pool);
        uint256 coinsLength;
        // Figure out how many tokens are in the curve pool.
        while (true) {
            try pool.coins(coinsLength) {
                ++coinsLength;
            } catch {
                break;
            }
        }

        // Only support LPs with 2 underlying assets.
        if (coinsLength != 2) {
            revert Curve2PoolLPAdaptor__UnsupportedPool();
        }

        address underlying;
        for (uint256 i; i < coinsLength; ) {
            underlying = pool.coins(i++);

            if (
                underlying != data.underlyingOrConstituent0 &&
                underlying != data.underlyingOrConstituent1
            ) {
                revert Curve2PoolLPAdaptor__UnsupportedPool();
            }
        }

        // Convert the parameters from `basis points` to `WAD` form,
        // while inefficient consistently entering parameters in
        // `basis points` minimizes potential human error,
        // even if it costs a bit extra gas on configuration.
        data.lowerBound = _bpToWad(data.lowerBound);
        data.upperBound = _bpToWad(data.upperBound);

        // Validate that the range between bounds is not too large.
        if (_MAX_BOUND_RANGE + data.lowerBound < data.upperBound) {
            revert Curve2PoolLPAdaptor__InvalidBounds();
        }

        // Make sure isCorrelated is correct for `pool`.
        if (data.isCorrelated) {
            // If assets are correlated, there will not be a lp_price()
            // function, so this should hit the catch statement.
            try pool.lp_price() {
                revert Curve2PoolLPAdaptor__UnsupportedPool();
            } catch {}
        } else {
            // If assets are not correlated, there will be a lp_price()
            // function, so this should hit the try statement.
            try pool.lp_price() {} catch {
                revert Curve2PoolLPAdaptor__UnsupportedPool();
            }
        }

        // Validate we can pull a virtual price.
        uint256 testVirtualPrice = pool.get_virtual_price();

        // Validate the virtualPrice is within the desired bounds.
        _enforceBounds(testVirtualPrice, data.lowerBound, data.upperBound);

        adaptorData[asset] = data;

        // Notify the adaptor to support the asset.
        isSupportedAsset[asset] = true;
        emit CurvePoolAssetAdded(asset, data);
    }

    /// @notice Removes a supported asset from the adaptor.
    /// @dev Calls back into price router to notify it of its removal.
    function removeAsset(address asset) external override {
        _checkElevatedPermissions();

        if (!isSupportedAsset[asset]) {
            revert Curve2PoolLPAdaptor__AssetIsNotSupported();
        }

        // Notify the adaptor to stop supporting the asset.
        delete isSupportedAsset[asset];
        // Wipe config mapping entries for a gas refund.
        delete adaptorData[asset];

        // Notify the price router that we are going to stop supporting
        // the asset.
        IOracleRouter(centralRegistry.oracleRouter()).notifyFeedRemoval(asset);
        emit CurvePoolAssetRemoved(asset);
    }

    function raiseBounds(
        address asset,
        uint256 newLowerBound,
        uint256 newUpperBound
    ) external {
        _checkElevatedPermissions();

        // Convert the parameters from `basis points` to `WAD` form,
        // while inefficient consistently entering parameters in
        // `basis points` minimizes potential human error,
        // even if it costs a bit extra gas on configuration.
        newLowerBound = _bpToWad(newLowerBound);
        newUpperBound = _bpToWad(newUpperBound);

        AdaptorData storage data = adaptorData[asset];
        uint256 oldLowerBound = data.lowerBound;
        uint256 oldUpperBound = data.upperBound;

        // Validate that the upper bound is greater than the lower bound.
        if (newLowerBound >= newUpperBound) {
            revert Curve2PoolLPAdaptor__InvalidBounds();
        }

        // Validate that the range between bounds is not too large.
        if (_MAX_BOUND_RANGE + newLowerBound < newUpperBound) {
            revert Curve2PoolLPAdaptor__InvalidBounds();
        }

        // Validate that the new bounds are higher than the old ones,
        // since virtual prices only rise overtime,
        // so they should never be decreased here.
        if (newLowerBound <= oldLowerBound || newUpperBound <= oldUpperBound) {
            revert Curve2PoolLPAdaptor__InvalidBounds();
        }

        if (oldLowerBound + _MAX_BOUND_INCREASE < newLowerBound) {
            revert Curve2PoolLPAdaptor__InvalidBounds();
        }

        if (oldUpperBound + _MAX_BOUND_INCREASE < newUpperBound) {
            revert Curve2PoolLPAdaptor__InvalidBounds();
        }

        uint256 testVirtualPrice = ICurvePool(data.pool).get_virtual_price();
        // Validate the virtualPrice is within the desired bounds.
        _enforceBounds(testVirtualPrice, newLowerBound, newUpperBound);

        data.lowerBound = newLowerBound;
        data.upperBound = newUpperBound;
    }

    /// @notice Checks if `price` is within a reasonable bound.
    function _enforceBounds(
        uint256 price,
        uint256 lowerBound,
        uint256 upperBound
    ) internal view {
        if (price < lowerBound || price > upperBound) {
            revert Curve2PoolLPAdaptor__BoundsExceeded();
        }
    }

    /// @dev Internal helper function for easily converting between scalars
    function _bpToWad(uint256 value) internal pure returns (uint256) {
        // multiplies by 1e14 to convert from basis points to WAD
        return value * 100000000000000;
    }
}
