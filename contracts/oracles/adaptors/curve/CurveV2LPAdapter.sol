// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import { BaseOracleAdaptor } from "contracts/oracles/adaptors/BaseOracleAdaptor.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";
import { IPriceRouter } from "contracts/interfaces/IPriceRouter.sol";
import { ICurvePool } from "contracts/interfaces/external/curve/ICurvePool.sol";

contract CurveV2LPAdapter is BaseOracleAdaptor {
    error CurveV2LPAdapter__UnsupportedPool();
    error CurveV2LPAdapter__DidNotConverge();

    // Technically I think curve pools will at most have 3 assets
    // or atleast the majority have 2-3
    // so we could replace this struct with 5 addresses.
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

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_
    ) BaseOracleAdaptor(centralRegistry_) {}

    /// EXTERNAL FUNCTIONS ///

    /// @notice Add a Balancer Stable Pool Bpt as an asset.
    /// @dev Should be called before `PriceRotuer:addAssetPriceFeed` is called.
    /// @param asset the address of the bpt to add
    function addAsset(
        address asset,
        address pool
    ) external onlyElevatedPermissions {
        require(
            !isSupportedAsset[asset],
            "CurveV2LPAdapter: asset already supported"
        );

        uint8 coinsLength = 0;
        // Figure out how many tokens are in the curve pool.
        while (true) {
            try ICurvePool(pool).coins(coinsLength) {
                ++coinsLength;
            } catch {
                break;
            }
        }
        if (coinsLength != 2 && coinsLength != 3)
            revert CurveV2LPAdapter__UnsupportedPool();

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
        IPriceRouter(centralRegistry.priceRouter())
            .notifyAssetPriceFeedRemoval(asset);
    }

    function getPrice(
        address asset,
        bool inUSD,
        bool getLower
    ) external view override returns (PriceReturnData memory pData) {
        pData.inUSD = inUSD;

        AdaptorData memory adapter = adaptorData[asset];
        IPriceRouter priceRouter = IPriceRouter(centralRegistry.priceRouter());
        (uint256 price0, uint256 errorCode) = priceRouter.getPrice(
            adapter.coins[0],
            inUSD,
            getLower
        );
        if (errorCode > 0) {
            pData.hadError = true;
            if (errorCode == BAD_SOURCE) return pData;
        }

        ICurvePool pool = ICurvePool(adapter.pool);
        if (adapter.coins.length == 2) {
            uint256 poolLpPrice = pool.lp_price();
            pData.price = uint240((poolLpPrice * price0) / 1e18);
        } else if (adapter.coins.length == 3) {
            uint256 virtualPrice = pool.get_virtual_price();
            uint256 t1Price = pool.price_oracle(0);
            uint256 t2Price = pool.price_oracle(1);
            uint256 maxPrice = (3 *
                virtualPrice *
                _cubicRoot(t1Price * t2Price)) / 1e18;

            {
                uint256 g = (pool.gamma() * 1e18) / GAMMA0;
                uint256 a = (pool.A() * 1e18) / A0;
                uint256 coefficient = (g ** 2 / 1e18) * a;
                uint256 discount = coefficient > 1e34 ? coefficient : 1e34;
                discount = (_cubicRoot(discount) * DISCOUNT0) / 1e18;

                maxPrice -= (maxPrice * discount) / 1e18;
            }

            pData.price = uint240((maxPrice * price0) / 1e18);
        }
    }

    /// INTERNAL FUNCTIONS ///

    /// @dev x has 36 decimals
    /// result has 18 decimals.
    function _cubicRoot(uint256 x) internal pure returns (uint256) {
        uint256 D = x / 1e18;
        for (uint8 i; i < 256; ++i) {
            uint256 diff;
            uint256 D_prev = D;
            D =
                (D * (2 * 1e18 + ((((x / D) * 1e18) / D) * 1e18) / D)) /
                (3 * 1e18);
            if (D > D_prev) diff = D - D_prev;
            else diff = D_prev - D;
            if (diff <= 1 || diff * 10 ** 18 < D) return D;
        }
        revert CurveV2LPAdapter__DidNotConverge();
    }
}
