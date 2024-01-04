// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { BaseOracleAdaptor } from "contracts/oracles/adaptors/BaseOracleAdaptor.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IPriceRouter } from "contracts/interfaces/IPriceRouter.sol";
import { IUniswapV2Pair } from "contracts/interfaces/external/uniswap/IUniswapV2Pair.sol";
import { Math } from "contracts/libraries/Math.sol";

contract BaseStableLPAdaptor is BaseOracleAdaptor {
    /// TYPES ///

    /// @notice Adaptor storage
    /// @param token0 token0 address
    /// @param decimals0 token0 decimals
    /// @param token1 token1 address
    /// @param decimals1 token1 decimals
    struct AdaptorData {
        address token0;
        uint8 decimals0;
        address token1;
        uint8 decimals1;
    }

    /// STORAGE ///

    /// @notice Balancer Stable Pool Adaptor Storage
    mapping(address => AdaptorData) public adaptorData;

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_
    ) BaseOracleAdaptor(centralRegistry_) {}

    /// EXTERNAL FUNCTIONS ///

    /// @notice Called during pricing operations.
    /// @param asset The bpt being priced
    /// @param inUSD Indicates whether we want the price in USD or ETH
    /// @param getLower Since this adaptor calls back into the price router
    ///                 it needs to know if it should be working with the
    ///                 upper or lower prices of assets
    function getPrice(
        address asset,
        bool inUSD,
        bool getLower
    ) external view virtual override returns (PriceReturnData memory) {
        return _getPrice(asset, inUSD, getLower);
    }

    /// @notice Add a Balancer Stable Pool Bpt as an asset.
    /// @dev Should be called before `PriceRotuer:addAssetPriceFeed` is called.
    /// @param asset The address of the bpt to add
    function addAsset(address asset) external virtual {
        _checkElevatedPermissions();
        _addAsset(asset);
    }

    /// @notice Removes a supported asset from the adaptor.
    /// @dev Calls back into price router to notify it of its removal
    function removeAsset(
        address asset
    ) external virtual override {
        _checkElevatedPermissions();
        _removeAsset(asset);
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Add a Balancer Stable Pool Bpt as an asset.
    /// @dev Should be called before `PriceRotuer:addAssetPriceFeed` is called.
    /// @param asset The address of the bpt to add
    function _addAsset(
        address asset
    ) internal returns (AdaptorData memory data) {
        IUniswapV2Pair pool = IUniswapV2Pair(asset);
        data.token0 = pool.token0();
        data.token1 = pool.token1();
        data.decimals0 = IERC20(data.token0).decimals();
        data.decimals1 = IERC20(data.token1).decimals();

        // Save values in Adaptor storage.
        adaptorData[asset] = data;
        isSupportedAsset[asset] = true;
        return data;
    }

    /// @notice Removes a supported asset from the adaptor.
    /// @dev Calls back into price router to notify it of its removal
    function _removeAsset(address asset) internal {
        // Notify the adaptor to stop supporting the asset
        delete isSupportedAsset[asset];
        // Wipe config mapping entries for a gas refund
        delete adaptorData[asset];

        // Notify the price router that we are going to stop supporting the asset
        IPriceRouter(centralRegistry.priceRouter()).notifyFeedRemoval(asset);
    }

    /// @notice Called during pricing operations.
    /// @dev https://blog.alphaventuredao.io/fair-lp-token-pricing/
    /// @param asset The bpt being priced
    /// @param inUSD Indicates whether we want the price in USD or ETH
    /// @param getLower Since this adaptor calls back into the price router
    ///                 it needs to know if it should be working with the
    ///                 upper or lower prices of assets
    function _getPrice(
        address asset,
        bool inUSD,
        bool getLower
    ) internal view returns (PriceReturnData memory pData) {
        // Read Adaptor storage and grab pool tokens
        AdaptorData memory data = adaptorData[asset];
        IUniswapV2Pair pool = IUniswapV2Pair(asset);

        // LP total supply
        uint256 totalSupply = pool.totalSupply();
        // LP reserves
        (uint256 reserve0, uint256 reserve1, ) = pool.getReserves();
        // convert to 18 decimals
        if (data.decimals0 != 18) {
            reserve0 = (reserve0 * 1e18) / (10 ** data.decimals0);
        }
        if (data.decimals1 != 18) {
            reserve1 = (reserve1 * 1e18) / (10 ** data.decimals1);
        }

        uint256 price0;
        uint256 price1;
        uint256 errorCode;
        IPriceRouter priceRouter = IPriceRouter(centralRegistry.priceRouter());
        (price0, errorCode) = priceRouter.getPrice(
            data.token0,
            inUSD,
            getLower
        );
        if (errorCode > 0) {
            pData.hadError = true;
            return pData;
        }
        (price1, errorCode) = priceRouter.getPrice(
            data.token1,
            inUSD,
            getLower
        );
        if (errorCode > 0) {
            pData.hadError = true;
            return pData;
        }

        uint256 finalPrice = _getFairPrice(reserve0, reserve1, price0, price1, totalSupply);

        if (_checkOracleOverflow(finalPrice)) {
            pData.hadError = true;
            return pData;
        }

        pData.inUSD = inUSD;
        pData.price = uint240(finalPrice);
    }

    function _getFairPrice(
        uint256 reserve0,
        uint256 reserve1,
        uint256 price0,
        uint256 price1,
        uint256 totalSupply
    ) internal pure returns (uint256 fairReserve) {
        // constant product = x^3 * y + x * y^3
        uint256 sqrtReserve = Math.sqrt(
            Math.sqrt(reserve0 * reserve1) *
                Math.sqrt(reserve0 * reserve0 + reserve1 * reserve1)
        );
        uint256 ratio = ((1e18) * price0) / price1;
        uint256 sqrtPrice = Math.sqrt(
            Math.sqrt((1e18) * ratio) * Math.sqrt(1e36 + ratio * ratio)
        );
        return
            ((((1e18) * sqrtReserve) / sqrtPrice) * price0 * 2) / totalSupply;
    }
}
