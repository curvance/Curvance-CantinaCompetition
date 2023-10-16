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

    // TO-DO add coin length here so we do not need to call .length to save an MLOAD
    struct AdaptorData {
        address[] coins;
        address pool;
    }

    /// CONSTANTS ///

    /// @notice Error code for bad source.
    uint256 public constant BAD_SOURCE = 2;

    uint256 private constant GAMMA0 = 28000000000000;
    uint256 private constant A0 = 2 * 3 ** 3 * 10000;
    uint256 private constant DISCOUNT0 = 1087460000000000;

    /// STORAGE ///

    /// @notice Curve Pool Adaptor Storage
    mapping(address => AdaptorData) public adaptorData;

    /// ERRORS ///

    error CurveAdaptor__UnsupportedPool();
    error CurveAdaptor__DidNotConverge();
    /// @dev Revert in the case when the `@nonreentrant('lock')` is activated in the Curve pool
    error NonreentrantLockIsActive();

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

    function getPrice(
        address asset,
        bool inUSD,
        bool getLower
    ) external view override returns (PriceReturnData memory pData) {
        pData.inUSD = inUSD;

        AdaptorData memory adapter = adaptorData[asset];
        if (isLocked(adapter.pool)) revert NonreentrantLockIsActive();

        IPriceRouter priceRouter = IPriceRouter(centralRegistry.priceRouter());
        ICurvePool pool = ICurvePool(adapter.pool);

        uint256 virtualPrice = pool.get_virtual_price();
        uint256 minPrice = type(uint256).max;
        for (uint256 i = 0; i < adapter.coins.length; ) {
            (uint256 price, uint256 errorCode) = priceRouter.getPrice(
                adapter.coins[i],
                inUSD,
                getLower
            );
            if (errorCode > 0) {
                pData.hadError = true;
                if (errorCode == BAD_SOURCE) return pData;
            }

            minPrice = minPrice < price ? minPrice : price;

            unchecked {
                i++;
            }
        }

        pData.price = uint240((minPrice * virtualPrice) / 1e18);
    }

    /// @notice Add a Balancer Stable Pool Bpt as an asset.
    /// @dev Should be called before `PriceRotuer:addAssetPriceFeed` is called.
    /// @param asset the address of the bpt to add
    function addAsset(
        address asset,
        address pool
    ) external onlyElevatedPermissions {
        require(
            !isSupportedAsset[asset],
            "CurveAdaptor: asset already supported"
        );

        uint256 coinsLength = 0;
        // Figure out how many tokens are in the curve pool.
        while (true) {
            try ICurvePool(pool).coins(coinsLength) {
                ++coinsLength;
            } catch {
                break;
            }
        }
        if (coinsLength != 2 && coinsLength != 3)
            revert CurveAdaptor__UnsupportedPool();

        address[] memory coins = new address[](coinsLength);
        for (uint256 i = 0; i < coinsLength; ++i) {
            coins[i] = ICurvePool(pool).coins(i);
        }

        // Save values in Adaptor storage.
        adaptorData[asset].coins = coins;
        adaptorData[asset].pool = pool;
        isSupportedAsset[asset] = true;
    }

    /// @notice Removes a supported asset from the adaptor.
    /// @dev Calls back into price router to notify it of its removal
    function removeAsset(address asset) external override onlyDaoPermissions {
        require(
            isSupportedAsset[asset],
            "VelodromeVolatileLPAdaptor: asset not supported"
        );

        // Notify the adaptor to stop supporting the asset
        delete isSupportedAsset[asset];
        // Wipe config mapping entries for a gas refund
        delete adaptorData[asset];

        // Notify the price router that we are going to stop supporting the asset
        IPriceRouter(centralRegistry.priceRouter()).notifyFeedRemoval(asset);
    }

}
