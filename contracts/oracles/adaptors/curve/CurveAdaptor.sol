// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import { BaseOracleAdaptor } from "contracts/oracles/adaptors/BaseOracleAdaptor.sol";
import { CurveReentrancyCheck } from "contracts/oracles/adaptors/curve/CurveReentrancyCheck.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";
import { IPriceRouter } from "contracts/interfaces/IPriceRouter.sol";
import { ICurvePool } from "contracts/interfaces/external/curve/ICurvePool.sol";

contract CurveAdaptor is BaseOracleAdaptor, CurveReentrancyCheck {
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

    /// ERRORS ///

    error CurveAdaptor__UnsupportedPool();
    error CurveAdaptor__DidNotConverge();
    error CurveAdaptor__Reentrant();
    error CurveAdaptor__AssetIsAlreadyAdded();
    error CurveAdaptor__AssetIsNotSupported();

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_
    ) BaseOracleAdaptor(centralRegistry_) {}

    /// EXTERNAL FUNCTIONS ///

    /// @inheritdoc CurveReentrancyCheck
    function setReentrancyVerificationConfig(
        address _pool,
        uint128 _gasLimit,
        CurveReentrancyCheck.N_COINS _nCoins
    ) external override onlyElevatedPermissions {
        _setReentrancyVerificationConfig(_pool, _gasLimit, _nCoins);
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
        if (isLocked(adapter.pool)) {
            revert CurveAdaptor__Reentrant();
        }

        IPriceRouter priceRouter = IPriceRouter(centralRegistry.priceRouter());
        ICurvePool pool = ICurvePool(adapter.pool);

        uint256 coins = adapter.coinsLength;
        uint256 virtualPrice = pool.get_virtual_price();
        uint256 minPrice = type(uint256).max;

        for (uint256 i; i < coins; ) {
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
    ) external onlyElevatedPermissions {
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

        AdaptorData storage newAsset = adaptorData[asset];

        // Save values in Adaptor storage.
        newAsset.coinsLength = coinsLength;
        newAsset.coins = coins;
        newAsset.pool = pool;

        // Notify the adaptor to support the asset
        isSupportedAsset[asset] = true;
    }

    /// @notice Removes a supported asset from the adaptor.
    /// @dev Calls back into price router to notify it of its removal
    function removeAsset(address asset) external override onlyDaoPermissions {
        if (!isSupportedAsset[asset]) {
            revert CurveAdaptor__AssetIsNotSupported();
        }

        // Notify the adaptor to stop supporting the asset
        delete isSupportedAsset[asset];
        // Wipe config mapping entries for a gas refund
        delete adaptorData[asset];

        // Notify the price router that we are going to stop supporting the asset
        IPriceRouter(centralRegistry.priceRouter()).notifyFeedRemoval(asset);
    }
}
