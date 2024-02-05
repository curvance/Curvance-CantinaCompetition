// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CurveBaseAdaptor } from "contracts/oracles/adaptors/curve/CurveBaseAdaptor.sol";
import { WAD } from "contracts/libraries/Constants.sol";
import { CommonLib } from "contracts/libraries/CommonLib.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";
import { IOracleRouter } from "contracts/interfaces/IOracleRouter.sol";
import { ICurvePool } from "contracts/interfaces/external/curve/ICurvePool.sol";
import { ERC20 } from "contracts/libraries/external/ERC20.sol";

/// @notice NOTE: BE CAREFUL USING THIS FEED, ALTHOUGH IT HAS MANY PROTECTIVE
///               LAYERS ITS STILL INTENDED TO BE COMBINED WITH OTHER ORACLE
///               SOLUTIONS. DO NOT USE THIS ORACLE BY ITSELF.
contract Curve2PoolAssetAdaptor is CurveBaseAdaptor {
    /// TYPES ///

    /// @notice Stores configuration data for Curve LP price sources.
    /// @param pool The address of the LP token/Curve pool.
    /// @param baseToken The address of asset that the adaptor is trying
    ///                  to price.
    /// @param baseTokenIndex The index inside coins() corresponding
    ///                       to `baseToken`.
    /// @param quoteTokenIndex The index inside coins() corresponding
    ///                        to the asset that `baseToken` is priced in.
    /// @param baseTokenDecimals The decimals of `baseToken`.
    /// @param quoteTokenDecimals The decimals of the token at `quoteTokenIndex`.
    /// @param upperBound Upper bound allowed for an LP token's virtual price.
    /// @param lowerBound Lower bound allowed for an LP token's virtual price.
    struct AdaptorData {
        address pool;
        address baseToken;
        int128 baseTokenIndex;
        int128 quoteTokenIndex;
        uint256 baseTokenDecimals;
        uint256 quoteTokenDecimals;
        uint256 upperBound;
        uint256 lowerBound;
    }

    /// CONSTANTS ///

    /// @notice Maximum bound range that can be increased on either side,
    ///         this is not meant to be anti tamperproof but,
    ///         more-so mitigate any human error.
    ///         .02e18 = 2%.
    uint256 internal constant _MAX_BOUND_INCREASE = .02e18;
    /// @notice Maximum difference between lower bound and upper bound,
    ///         checked on configuration.
    ///         .05e18 = 5%.
    uint256 internal constant _MAX_BOUND_RANGE = .05e18;

    /// STORAGE ///

    /// @notice Adaptor configuration data for pricing an asset.
    /// @dev Curve asset address => AdaptorData.
    mapping(address => AdaptorData) public adaptorData;

    /// EVENTS ///

    event CurvePoolAssetAdded(
        address asset, 
        AdaptorData assetConfig, 
        bool isUpdate
    );
    event CurvePoolAssetRemoved(address asset);

    /// ERRORS ///

    error Curve2PoolAssetAdaptor__Reentrant();
    error Curve2PoolAssetAdaptor__BoundsExceeded();
    error Curve2PoolAssetAdaptor__UnsupportedPool();
    error Curve2PoolAssetAdaptor__AssetIsNotSupported();
    error Curve2PoolAssetAdaptor__BaseAssetIsNotSupported();
    error Curve2PoolAssetAdaptor__InvalidBounds();
    error Curve2PoolAssetAdaptor__InvalidAsset();
    error Curve2PoolAssetAdaptor__InvalidAssetIndex();

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_
    ) CurveBaseAdaptor(centralRegistry_) {}

    /// EXTERNAL FUNCTIONS ///

    /// @notice Sets or updates a Curve pool configuration for the reentrancy
    ///         check.
    /// @param coinsLength The number of coins (from .coinsLength) on the
    ///                    Curve pool.
    /// @param gasLimit The gas limit to be set on the check.
    function setReentrancyConfig(
        uint256 coinsLength,
        uint256 gasLimit
    ) external {
        _checkElevatedPermissions();
        _setReentrancyConfig(coinsLength, gasLimit);
    }

    /// @notice Retrieves the price of `asset` from Curve's built in oracle price.
    /// @dev Price is returned in USD or ETH depending on 'inUSD' parameter.
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
        AdaptorData memory data = adaptorData[asset];
        
        // Validate we support this pool and that this is not
        // a reeentrant call.
        if (isLocked(data.pool, 2)) {
            revert Curve2PoolAssetAdaptor__Reentrant();
        }

        // Cache the curve pool.
        ICurvePool pool = ICurvePool(data.pool);

        // Make sure virtualPrice is reasonable.
        uint256 virtualPrice = pool.get_virtual_price();
        _enforceBounds(virtualPrice, data.lowerBound, data.upperBound);

        // Get underlying token prices.
        IOracleRouter oracleRouter = IOracleRouter(
            centralRegistry.oracleRouter()
        );
        (uint256 basePrice, uint256 errorCode) = oracleRouter.getPrice(
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

        uint256 price = (out * WAD * (10 ** data.quoteTokenDecimals)) /
            sample /
            (10 ** data.baseTokenDecimals); // in base token decimals

        price = (price * basePrice) / WAD;

        if (_checkOracleOverflow(price)) {
            pData.hadError = true;
            return pData;
        }

        pData.inUSD = inUSD;
        pData.price = uint240(price);
    }

    /// @notice Adds pricing support for `asset`, an asset inside
    ///         a Curve V2 pool.
    /// @dev Should be called before `OracleRouter:addAssetPriceFeed`
    ///      is called.
    /// @param asset The address of the token to add pricing support for.
    /// @param data The adaptor data needed to add `asset`.
    function addAsset(address asset, AdaptorData memory data) external {
        _checkElevatedPermissions();

        // Make sure that the asset being added has the proper input
        // via this sanity check.
        if (isLocked(data.pool, 2)) {
            revert Curve2PoolAssetAdaptor__UnsupportedPool();
        }

        // Make sure `asset` is not trying to price denominated in itself.
        if (asset == data.baseToken) {
            revert Curve2PoolAssetAdaptor__InvalidAsset();
        }

        address oracleRouter = centralRegistry.oracleRouter();

        // Make sure that the price denomination asset is supported
        // by the Oracle Router.
        if (!IOracleRouter(oracleRouter).isSupportedAsset(data.baseToken)) {
            revert Curve2PoolAssetAdaptor__BaseAssetIsNotSupported();
        }

        // Validate that the upper bound is greater than the lower bound.
        if (data.lowerBound >= data.upperBound) {
            revert Curve2PoolAssetAdaptor__InvalidBounds();
        }

        ICurvePool pool = ICurvePool(data.pool);
        // Make sure that the asset matches the pools quote token.
        if (pool.coins(uint256(uint128(data.quoteTokenIndex))) != asset) {
            revert Curve2PoolAssetAdaptor__InvalidAssetIndex();
        }
        if (
            pool.coins(uint256(uint128(data.baseTokenIndex))) != data.baseToken
        ) {
            revert Curve2PoolAssetAdaptor__InvalidAssetIndex();
        }

        data.quoteTokenDecimals = ERC20(asset).decimals();
        // Dynamically pull the decimals from the base token contract.
        if (CommonLib.isETH(data.baseToken)) {
            data.baseTokenDecimals = 18;
        } else {
            data.baseTokenDecimals = ERC20(data.baseToken).decimals();
        }

        // Convert the parameters from `basis points` to `WAD` form,
        // while inefficient consistently entering parameters in
        // `basis points` minimizes potential human error,
        // even if it costs a bit extra gas on configuration.
        data.lowerBound = _bpToWad(data.lowerBound);
        data.upperBound = _bpToWad(data.upperBound);

        // Validate that the range between bounds is not too large.
        if (_MAX_BOUND_RANGE + data.lowerBound < data.upperBound) {
            revert Curve2PoolAssetAdaptor__InvalidBounds();
        }

        // Validate we can pull a virtual price.
        uint256 testVirtualPrice = pool.get_virtual_price();

        // Validate the virtualPrice is within the desired bounds.
        _enforceBounds(testVirtualPrice, data.lowerBound, data.upperBound);

        // Save adaptor data and update mapping that we support `asset` now.
        adaptorData[asset] = data;

        // Check whether this is new or updated support for `asset`.
        bool isUpdate;
        if (isSupportedAsset[asset]) {
            isUpdate = true;
        }

        isSupportedAsset[asset] = true;
        emit CurvePoolAssetAdded(asset, data, isUpdate);
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
            revert Curve2PoolAssetAdaptor__AssetIsNotSupported();
        }

        // Wipe config mapping entries for a gas refund.
        // Notify the adaptor to stop supporting the asset.
        delete isSupportedAsset[asset];
        delete adaptorData[asset];

        // Notify the Oracle Router that we are going to stop supporting
        // the asset.
        IOracleRouter(centralRegistry.oracleRouter()).notifyFeedRemoval(asset);
        emit CurvePoolAssetRemoved(asset);
    }

    /// @notice Raises virtual price bounds for `asset`. Must be greater than
    ///         old bounds, cannot be more than `_MAX_BOUND_RANGE` apart.
    /// @dev Reverts if the new bounds are not larger than the old ones,
    ///      as virtual price should always be increasing,
    ///      barring a pool exploit.
    /// @param asset The address of the asset to update virtual price
    ///              bounds for.
    /// @param newLowerBound The new lower bound to make sure `price`
    ///                      is greater than.
    /// @param newUpperBound The new upper bound to make sure `price`
    ///                      is less than.
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
        // Cache the old virtual price bounds.
        uint256 oldLowerBound = data.lowerBound;
        uint256 oldUpperBound = data.upperBound;

        // Validate that the upper bound is greater than the lower bound.
        if (newLowerBound >= newUpperBound) {
            revert Curve2PoolAssetAdaptor__InvalidBounds();
        }

        // Validate that the range between bounds is not too large.
        if (_MAX_BOUND_RANGE + newLowerBound < newUpperBound) {
            revert Curve2PoolAssetAdaptor__InvalidBounds();
        }

        // Validate that the new bounds are higher than the old ones,
        // since virtual prices only rise overtime,
        // so they should never be decreased here.
        if (newLowerBound <= oldLowerBound || newUpperBound <= oldUpperBound) {
            revert Curve2PoolAssetAdaptor__InvalidBounds();
        }

        if (oldLowerBound + _MAX_BOUND_INCREASE < newLowerBound) {
            revert Curve2PoolAssetAdaptor__InvalidBounds();
        }

        if (oldUpperBound + _MAX_BOUND_INCREASE < newUpperBound) {
            revert Curve2PoolAssetAdaptor__InvalidBounds();
        }

        data.lowerBound = newLowerBound;
        data.upperBound = newUpperBound;
    }

    /// @notice Helper function to check if `price` is within a reasonable
    ///         bound. 
    /// @dev Reverts if bounds are breached.
    /// @param virtualPrice The virtual price to check against `lowerBound`
    ///                     and `upperBound`.
    /// @param lowerBound The lower bound to make sure `price` is greater than.
    /// @param upperBound The upper bound to make sure `price` is less than.
    function _enforceBounds(
        uint256 virtualPrice,
        uint256 lowerBound,
        uint256 upperBound
    ) internal pure {
        if (virtualPrice < lowerBound || virtualPrice > upperBound) {
            revert Curve2PoolAssetAdaptor__BoundsExceeded();
        }
    }

    /// @notice Multiplies `value` by 1e14 to convert it from `basis points`
    ///         to WAD.
    /// @dev Internal helper function for easily converting between scalars.
    function _bpToWad(uint256 value) internal pure returns (uint256) {
        return value * 1e14;
    }
}
