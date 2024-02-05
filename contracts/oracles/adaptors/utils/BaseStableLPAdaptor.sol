// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { BaseOracleAdaptor } from "contracts/oracles/adaptors/BaseOracleAdaptor.sol";
import { FixedPointMathLib } from "contracts/libraries/FixedPointMathLib.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IOracleRouter } from "contracts/interfaces/IOracleRouter.sol";
import { IUniswapV2Pair } from "contracts/interfaces/external/uniswap/IUniswapV2Pair.sol";

abstract contract BaseStableLPAdaptor is BaseOracleAdaptor {
    /// TYPES ///

    /// @notice Stores configuration data for Uniswap V2 stable style
    ///         Twap price sources.
    /// @param token0 Underlying token0 address.
    /// @param decimals0 Underlying decimals for token0.
    /// @param token1 Underlying token1 address.
    /// @param decimals1 Underlying decimals for token1.
    struct AdaptorData {
        address token0;
        uint8 decimals0;
        address token1;
        uint8 decimals1;
    }

    /// STORAGE ///

    /// @notice Adaptor configuration data for pricing an asset.
    /// @dev Stable pool address => AdaptorData.
    mapping(address => AdaptorData) public adaptorData;

    /// ERRORS ///

    error BaseStableLPAdaptor__AssetIsNotSupported();

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_
    ) BaseOracleAdaptor(centralRegistry_) {}

    /// EXTERNAL FUNCTIONS ///

    /// @notice Retrieves the price of `asset`, an lp token, 
    ///         for a Univ2 style stable pool.
    /// @dev Price is returned in USD or ETH depending on 'inUSD' parameter.
    /// @param asset The address of the asset for which the price is needed.
    /// @param inUSD A boolean to determine if the price should be returned in
    ///              USD or not.
    /// @param getLower A boolean to determine if lower of two oracle prices
    ///                 should be retrieved.
    /// @return A structure containing the price, error status,
    ///         and the quote format of the price.
    function getPrice(
        address asset,
        bool inUSD,
        bool getLower
    ) external view virtual override returns (PriceReturnData memory) {
        return _getPrice(asset, inUSD, getLower);
    }

    /// @notice Adds pricing support for `asset`, an lp token for
    ///         a Univ2 style stable liquidity pool.
    /// @dev Should be called before `OracleRouter:addAssetPriceFeed`
    ///      is called.
    /// @param asset The address of the lp token to support pricing for.
    function addAsset(address asset) external virtual {
        _checkElevatedPermissions();
        _addAsset(asset);
    }

    /// @notice Removes a supported asset from the adaptor.
    /// @dev Calls back into Oracle Router to notify it of its removal.
    ///      Requires that `asset` is currently supported.
    /// @param asset The address of the supported asset to remove from
    ///              the adaptor.
    function removeAsset(
        address asset
    ) external virtual override {
        _checkElevatedPermissions();
        _removeAsset(asset);
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Retrieves the price of `asset`, an lp token, 
    ///         for a Univ2 style stable pool.
    /// @dev Math source: https://blog.alphaventuredao.io/fair-lp-token-pricing/
    /// @param asset The address of the asset for which the price is needed.
    /// @param inUSD A boolean to determine if the price should be returned in
    ///              USD or not.
    /// @param getLower A boolean to determine if lower of two oracle prices
    ///                 should be retrieved.
    /// @return pData A structure containing the price, error status,
    ///               and the quote format of the price.
    function _getPrice(
        address asset,
        bool inUSD,
        bool getLower
    ) internal view returns (PriceReturnData memory pData) {
        // Validate we support pricing `asset`.
        if (!isSupportedAsset[asset]) {
            revert BaseStableLPAdaptor__AssetIsNotSupported();
        }

        // Read Adaptor storage and grab pool tokens.
        AdaptorData memory data = adaptorData[asset];
        IUniswapV2Pair pool = IUniswapV2Pair(asset);

        // Query LP total supply.
        uint256 totalSupply = pool.totalSupply();
        // Query LP reserves.
        (uint256 reserve0, uint256 reserve1, ) = pool.getReserves();
        // convert to 18 decimals.
        if (data.decimals0 != 18) {
            reserve0 = (reserve0 * 1e18) / (10 ** data.decimals0);
        }

        if (data.decimals1 != 18) {
            reserve1 = (reserve1 * 1e18) / (10 ** data.decimals1);
        }

        uint256 price0;
        uint256 price1;
        uint256 errorCode;

        IOracleRouter oracleRouter = IOracleRouter(centralRegistry.oracleRouter());
        (price0, errorCode) = oracleRouter.getPrice(
            data.token0,
            inUSD,
            getLower
        );

        // Validate we did not run into any errors pricing token0.
        if (errorCode > 0) {
            pData.hadError = true;
            return pData;
        }

        (price1, errorCode) = oracleRouter.getPrice(
            data.token1,
            inUSD,
            getLower
        );

        // Validate we did not run into any errors pricing token1.
        if (errorCode > 0) {
            pData.hadError = true;
            return pData;
        }

        uint256 finalPrice = _getFairPrice(reserve0, reserve1, price0, price1, totalSupply);

        // Validate price will not overflow on conversion to uint240.
        if (_checkOracleOverflow(finalPrice)) {
            pData.hadError = true;
            return pData;
        }

        pData.inUSD = inUSD;
        pData.price = uint240(finalPrice);
    }

    /// @notice Helper function for pricing support for `asset`, 
    ///         an lp token for a Univ2 style stable liquidity pool.
    /// @dev Should be called before `OracleRouter:addAssetPriceFeed`
    ///      is called.
    /// @param asset The address of the lp token to add pricing support for.
    function _addAsset(
        address asset
    ) internal returns (AdaptorData memory data) {

        IUniswapV2Pair pool = IUniswapV2Pair(asset);
        data.token0 = pool.token0();
        data.token1 = pool.token1();
        data.decimals0 = IERC20(data.token0).decimals();
        data.decimals1 = IERC20(data.token1).decimals();

        // Save adaptor data and update mapping that we support `asset` now.
        adaptorData[asset] = data;
        isSupportedAsset[asset] = true;
        return data;
    }

    /// @notice Helper function to remove a supported asset from the adaptor.
    /// @dev Calls back into oracle router to notify it of its removal.
    ///      Requires that `asset` is currently supported.
    /// @param asset The address of the supported asset to remove from
    ///              the adaptor.
    function _removeAsset(address asset) internal {
        // Validate that `asset` is currently supported.
        if (!isSupportedAsset[asset]) {
            revert BaseStableLPAdaptor__AssetIsNotSupported();
        }

        // Wipe config mapping entries for a gas refund.
        // Notify the adaptor to stop supporting the asset.
        delete isSupportedAsset[asset];
        delete adaptorData[asset];

        // Notify the oracle router that we are going to stop supporting
        // the asset.
        IOracleRouter(centralRegistry.oracleRouter()).notifyFeedRemoval(asset);
    }

    /// @notice Helper function in calculating the price of an lp token. 
    ///         Uses reserves, and pricing of each underlying token versus
    ///         the total supply of lp tokens making up the pool.
    /// @param reserve0 The amount of underlying token0 inside the liquidity pool.
    /// @param reserve1 The amount of underlying token1 inside the liquidity pool.
    /// @param price0 The price of token0 according to the Oracle Router.
    /// @param price0 The price of token1 according to the Oracle Router.
    /// @param totalSupply The total supply of lp tokens inside the lp.
    /// @return Fair value pricing for the lp token.
    function _getFairPrice(
        uint256 reserve0,
        uint256 reserve1,
        uint256 price0,
        uint256 price1,
        uint256 totalSupply
    ) internal pure returns (uint256) {
        // constant product = x^3 * y + x * y^3.
        uint256 sqrtReserve = FixedPointMathLib.sqrt(
            FixedPointMathLib.sqrt(reserve0 * reserve1) *
                FixedPointMathLib.sqrt(reserve0 * reserve0 + reserve1 * reserve1)
        );
        uint256 ratio = ((1e18) * price0) / price1;
        uint256 sqrtPrice = FixedPointMathLib.sqrt(
            FixedPointMathLib.sqrt((1e18) * ratio) * FixedPointMathLib.sqrt(1e36 + ratio * ratio)
        );
        return
            ((((1e18) * sqrtReserve) / sqrtPrice) * price0 * 2) / totalSupply;
    }
}
