// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CurveBaseAdaptor } from "contracts/oracles/adaptors/curve/CurveBaseAdaptor.sol";
import { WAD } from "contracts/libraries/Constants.sol";
import { FixedPointMathLib } from "contracts/libraries/external/FixedPointMathLib.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";
import { IPriceRouter } from "contracts/interfaces/IPriceRouter.sol";
import { ICurvePool } from "contracts/interfaces/external/curve/ICurvePool.sol";
import { ERC20 } from "contracts/libraries/external/ERC20.sol";

contract Curve2AssetAdaptor is CurveBaseAdaptor {
    /// TYPES ///

    struct AdaptorData {
        address pool;
        address baseToken;
        int128 quoteTokenIndex;
        int128 baseTokenIndex;
        uint256 quoteTokenDecimals;
        uint256 baseTokenDecimals;
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

    error Curve2AssetAdaptor__Reentrant();
    error Curve2AssetAdaptor__BoundsExceeded();
    error Curve2AssetAdaptor__UnsupportedPool();
    error Curve2AssetAdaptor__AssetIsAlreadyAdded();
    error Curve2AssetAdaptor__AssetIsNotSupported();
    error Curve2AssetAdaptor__BaseAssetIsNotSupported();
    error Curve2AssetAdaptor__InvalidBounds();
    error Curve2AssetAdaptor__InvalidAsset();
    error Curve2AssetAdaptor__InvalidAssetIndex();

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
            revert Curve2AssetAdaptor__Reentrant();
        }

        AdaptorData memory data = adaptorData[asset];
        ICurvePool pool = ICurvePool(data.pool);

        // Get underlying token prices.
        IPriceRouter priceRouter = IPriceRouter(centralRegistry.priceRouter());
        (uint256 basePrice, uint256 errorCode) = priceRouter.getPrice(
            data.baseToken,
            inUSD,
            getLower
        );
        if (errorCode > 0) {
            pData.hadError = true;
            return pData;
        }

        // take 1% of liquidity as sample
        uint256 sample = pool.balances(
            uint256(uint128(data.quoteTokenIndex))
        ) / 100;

        uint256 out = pool.get_dy(
            data.quoteTokenIndex,
            data.baseTokenIndex,
            sample
        );

        uint256 price = (out * (10 ** data.quoteTokenDecimals)) / sample; // in base token decimals

        price = (price * basePrice) / (10 ** data.baseTokenDecimals);

        if (_checkOracleOverflow(price)) {
            pData.hadError = true;
            return pData;
        }

        pData.price = uint240(price);
    }

    /// @notice Adds a Curve LP as an asset.
    /// @dev Should be called before `PriceRouter:addAssetPriceFeed` is called.
    /// @param asset the address of the lp to add
    function addAsset(address asset, AdaptorData memory data) external {
        _checkElevatedPermissions();

        if (isSupportedAsset[asset]) {
            revert Curve2AssetAdaptor__AssetIsAlreadyAdded();
        }

        // Make sure that the asset being added has the proper input
        // via this sanity check.
        if (isLocked(asset, 2)) {
            revert Curve2AssetAdaptor__UnsupportedPool();
        }

        if (asset == data.baseToken) {
            revert Curve2AssetAdaptor__InvalidAsset();
        }

        address priceRouter = centralRegistry.priceRouter();

        if (!IPriceRouter(priceRouter).isSupportedAsset(data.baseToken)) {
            revert Curve2AssetAdaptor__BaseAssetIsNotSupported();
        }

        // Validate that the upper bound is greater than the lower bound.
        if (data.lowerBound >= data.upperBound) {
            revert Curve2AssetAdaptor__InvalidBounds();
        }

        ICurvePool pool = ICurvePool(data.pool);
        if (pool.coins(uint256(uint128(data.quoteTokenIndex))) != asset) {
            revert Curve2AssetAdaptor__InvalidAssetIndex();
        }
        if (
            pool.coins(uint256(uint128(data.baseTokenIndex))) != data.baseToken
        ) {
            revert Curve2AssetAdaptor__InvalidAssetIndex();
        }

        data.quoteTokenDecimals = ERC20(asset).decimals();
        data.baseTokenDecimals = ERC20(data.baseToken).decimals();

        // Convert the parameters from `basis points` to `WAD` form,
        // while inefficient consistently entering parameters in
        // `basis points` minimizes potential human error,
        // even if it costs a bit extra gas on configuration.
        data.lowerBound = _bpToWad(data.lowerBound);
        data.upperBound = _bpToWad(data.upperBound);

        // Validate that the range between bounds is not too large.
        if (_MAX_BOUND_RANGE + data.lowerBound < data.upperBound) {
            revert Curve2AssetAdaptor__InvalidBounds();
        }

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
            revert Curve2AssetAdaptor__AssetIsNotSupported();
        }

        // Notify the adaptor to stop supporting the asset.
        delete isSupportedAsset[asset];
        // Wipe config mapping entries for a gas refund.
        delete adaptorData[asset];

        // Notify the price router that we are going to stop supporting
        // the asset.
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
            revert Curve2AssetAdaptor__InvalidBounds();
        }

        // Validate that the range between bounds is not too large.
        if (_MAX_BOUND_RANGE + newLowerBound < newUpperBound) {
            revert Curve2AssetAdaptor__InvalidBounds();
        }

        // Validate that the new bounds are higher than the old ones,
        // since virtual prices only rise overtime,
        // so they should never be decreased here.
        if (newLowerBound <= oldLowerBound || newUpperBound <= oldUpperBound) {
            revert Curve2AssetAdaptor__InvalidBounds();
        }

        if (oldLowerBound + _MAX_BOUND_INCREASE < newLowerBound) {
            revert Curve2AssetAdaptor__InvalidBounds();
        }

        if (oldUpperBound + _MAX_BOUND_INCREASE < newUpperBound) {
            revert Curve2AssetAdaptor__InvalidBounds();
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
            revert Curve2AssetAdaptor__BoundsExceeded();
        }
    }

    /// @dev Internal helper function for easily converting between scalars
    function _bpToWad(uint256 value) internal pure returns (uint256) {
        // multiplies by 1e14 to convert from basis points to WAD
        return value * 100000000000000;
    }
}
