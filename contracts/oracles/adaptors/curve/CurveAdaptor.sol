// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CurveBaseAdaptor } from "contracts/oracles/adaptors/curve/CurveBaseAdaptor.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";
import { IPriceRouter } from "contracts/interfaces/IPriceRouter.sol";
import { ICurvePool } from "contracts/interfaces/external/curve/ICurvePool.sol";

contract CurveAdaptor is CurveBaseAdaptor {
    /// TYPES ///

    struct AdaptorData {
        uint256 coinsLength;
        address[] coins;
        address pool;
    }

    /// CONSTANTS ///

    uint256 private constant GAMMA0 = 28000000000000;
    uint256 private constant A0 = 2 * 3 ** 3 * 10000;
    uint256 private constant DISCOUNT0 = 1087460000000000;

    /// STORAGE ///

    /// @notice Curve Pool Adaptor Storage
    mapping(address => AdaptorData) public adaptorData;

    /// EVENTS ///

    event CurvePoolAssetAdded(
        address asset,
        AdaptorData assetConfig
    );

    event CurvePoolAssetRemoved(address asset);

    /// ERRORS ///

    error CurveAdaptor__UnsupportedPool();
    error CurveAdaptor__DidNotConverge();
    error CurveAdaptor__Reentrant();
    error CurveAdaptor__AssetIsAlreadyAdded();
    error CurveAdaptor__AssetIsNotSupported();

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

        AdaptorData memory adapter = adaptorData[asset];
        ICurvePool pool = ICurvePool(adapter.pool);

        uint256 coinsLength = adapter.coinsLength;
        if (isLocked(asset, coinsLength)) {
            revert CurveAdaptor__Reentrant();
        }

        uint256 virtualPrice = pool.get_virtual_price();
        uint256 minPrice = type(uint256).max;
        IPriceRouter priceRouter = IPriceRouter(centralRegistry.priceRouter());

        for (uint256 i; i < coinsLength; ) {
            (uint256 price, uint256 errorCode) = priceRouter.getPrice(
                adapter.coins[i],
                inUSD,
                getLower
            );
            if (errorCode > 0) {
                pData.hadError = true;
                return pData;
            }

            minPrice = minPrice < price ? minPrice : price;

            unchecked {
                ++i;
            }
        }

        pData.price = uint240((minPrice * virtualPrice) / 1e18);
    }

    /// @notice Adds a Curve LP as an asset.
    /// @dev Should be called before `PriceRouter:addAssetPriceFeed` is called.
    /// @param asset the address of the lp to add
    function addAsset(
        address asset,
        address pool
    ) external {
        _checkElevatedPermissions();

        if (isSupportedAsset[asset]) {
            revert CurveAdaptor__AssetIsAlreadyAdded();
        }

        uint256 coinsLength;
        // Figure out how many tokens are in the curve pool.
        while (true) {
            try ICurvePool(pool).coins(coinsLength) {
                ++coinsLength;
            } catch {
                break;
            }
        }
        // Only support LPs with 2 - 4 underlying assets
        if (coinsLength > 4) {
            revert CurveAdaptor__UnsupportedPool();
        }

        address[] memory coins = new address[](coinsLength);
        for (uint256 i; i < coinsLength; ) {
            coins[i] = ICurvePool(pool).coins(i);

            unchecked {
                ++i;
            }
        }

        // Make sure that the asset being added has the proper input
        // via this sanity check
        if (isLocked(asset, coinsLength)){
            revert CurveAdaptor__UnsupportedPool();
        }

        AdaptorData storage newAsset = adaptorData[asset];

        // Save configuration values in adaptorData
        newAsset.coinsLength = coinsLength;
        newAsset.coins = coins;
        newAsset.pool = pool;

        // Notify the adaptor to support the asset
        isSupportedAsset[asset] = true;
        emit CurvePoolAssetAdded(asset, newAsset);
    }

    /// @notice Removes a supported asset from the adaptor.
    /// @dev Calls back into price router to notify it of its removal
    function removeAsset(address asset) external override {
        _checkElevatedPermissions();

        if (!isSupportedAsset[asset]) {
            revert CurveAdaptor__AssetIsNotSupported();
        }

        // Notify the adaptor to stop supporting the asset
        delete isSupportedAsset[asset];
        // Wipe config mapping entries for a gas refund
        delete adaptorData[asset];

        // Notify the price router that we are going to stop supporting the asset
        IPriceRouter(centralRegistry.priceRouter()).notifyFeedRemoval(asset);
        emit CurvePoolAssetRemoved(asset);
    }
}
