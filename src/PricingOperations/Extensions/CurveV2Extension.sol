// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import { ICurvePool } from "src/interfaces/Curve/ICurvePool.sol";
import { Extension } from "src/PricingOperations/Extension.sol";
import { PriceOps } from "src/PricingOperations/PriceOps.sol";
import { Math } from "src/utils/Math.sol";
import { AutomationCompatibleInterface } from "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";
import { ERC20, SafeTransferLib } from "src/base/ERC4626.sol";

import { console } from "@forge-std/Test.sol";

// TODO Add Chainlink Curve VP bound check
contract CurveV2Extension is Extension {
    using Math for uint256;

    error CurveV2Extension__UnsupportedPool();
    error CurveV2Extension__DidNotConverge();

    // Technically I think curve pools will at most have 3 assets, or atleast the majority have 2-3 so we could replace this struct with 5 addresses.
    struct CurveDerivativeStorage {
        address[] coins;
        address pool;
        address asset;
    }

    /**
     * @notice Curve Derivative Storage
     * @dev Stores an array of the underlying token addresses in the curve pool.
     */
    mapping(uint64 => CurveDerivativeStorage) public getCurveDerivativeStorage;

    constructor(PriceOps _priceOps) Extension(_priceOps) {}

    /**
     * @notice Setup function for pricing CurveV2 derivative assets.
     * @dev _source The address of the CurveV2 Pool.
     * @dev _storage A VirtualPriceBound value for this asset.
     * @dev Assumes that curve pools never add or remove tokens.
     */
    function setupSource(address asset, uint64 _sourceId, bytes memory data) external override onlyPriceOps {
        address _source = abi.decode(data, (address));
        ICurvePool pool = ICurvePool(_source);
        uint8 coinsLength = 0;
        // Figure out how many tokens are in the curve pool.
        while (true) {
            try pool.coins(coinsLength) {
                coinsLength++;
            } catch {
                break;
            }
        }
        if (coinsLength != 2 && coinsLength != 3) revert CurveV2Extension__UnsupportedPool();
        address[] memory coins = new address[](coinsLength);
        for (uint256 i = 0; i < coinsLength; i++) {
            coins[i] = pool.coins(i);
        }

        getCurveDerivativeStorage[_sourceId].coins = coins;
        getCurveDerivativeStorage[_sourceId].pool = _source;
        getCurveDerivativeStorage[_sourceId].asset = asset;

        // curveAssets.push(address(_asset));

        // Setup virtual price bound.
        // VirtualPriceBound memory vpBound = abi.decode(_storage, (VirtualPriceBound));
        // uint256 upper = uint256(vpBound.datum).mulDivDown(vpBound.posDelta, 1e8);
        // upper = upper.changeDecimals(8, 18);
        // uint256 lower = uint256(vpBound.datum).mulDivDown(vpBound.negDelta, 1e8);
        // lower = lower.changeDecimals(8, 18);
        // _checkBounds(lower, upper, pool.get_virtual_price());
        // if (vpBound.rateLimit == 0) vpBound.rateLimit = DEFAULT_RATE_LIMIT;
        // vpBound.timeLastUpdated = uint64(block.timestamp);
        // getVirtualPriceBound[address(_asset)] = vpBound;
    }

    uint256 private constant GAMMA0 = 28000000000000;
    uint256 private constant A0 = 2 * 3 ** 3 * 10000;
    uint256 private constant DISCOUNT0 = 1087460000000000;

    // x has 36 decimals
    // result has 18 decimals.
    function _cubicRoot(uint256 x) internal pure returns (uint256) {
        uint256 D = x / 1e18;
        for (uint8 i; i < 256; i++) {
            uint256 diff;
            uint256 D_prev = D;
            D = (D * (2 * 1e18 + ((((x / D) * 1e18) / D) * 1e18) / D)) / (3 * 1e18);
            if (D > D_prev) diff = D - D_prev;
            else diff = D_prev - D;
            if (diff <= 1 || diff * 10 ** 18 < D) return D;
        }
        revert CurveV2Extension__DidNotConverge();
    }

    /**
     * Inspired by https://etherscan.io/address/0xE8b2989276E2Ca8FDEA2268E3551b2b4B2418950#code
     * @notice Get the price of a CurveV2 derivative in terms of Base.
     */
    function getPriceInBase(
        uint64 sourceId
    ) external view override onlyPriceOps returns (uint256 upper, uint256 lower, uint8 errorCode) {
        CurveDerivativeStorage memory stor = getCurveDerivativeStorage[sourceId];

        ICurvePool pool = ICurvePool(stor.pool);

        // Check that virtual price is within bounds.
        uint256 virtualPrice = pool.get_virtual_price();
        // VirtualPriceBound memory vpBound = getVirtualPriceBound[address(asset)];
        // uint256 upper = uint256(vpBound.datum).mulDivDown(vpBound.posDelta, 1e8);
        // upper = upper.changeDecimals(8, 18);
        // uint256 lower = uint256(vpBound.datum).mulDivDown(vpBound.negDelta, 1e8);
        // lower = lower.changeDecimals(8, 18);
        // _checkBounds(lower, upper, virtualPrice);
        // TODO if VP check fails, then return an error code.

        uint256 token0Upper;
        uint256 token0Lower;
        (token0Upper, token0Lower, errorCode) = priceOps.getPriceInBase(stor.coins[0]);
        if (errorCode == BAD_SOURCE) return (0, 0, BAD_SOURCE);

        if (stor.coins.length == 2) {
            uint256 poolLpPrice = pool.lp_price();
            upper = poolLpPrice.mulDivDown(token0Upper, 1e18);
            lower = poolLpPrice.mulDivDown(token0Lower, 1e18);
        } else if (stor.coins.length == 3) {
            uint256 t1Price = pool.price_oracle(0); //btc to usdt 18 dec
            uint256 t2Price = pool.price_oracle(1); // eth to usdt 18 dec

            uint256 maxPrice = (3 * virtualPrice * _cubicRoot(t1Price * t2Price)) / 1e18;
            {
                uint256 g = pool.gamma().mulDivDown(1e18, GAMMA0);
                uint256 a = pool.A().mulDivDown(1e18, A0);
                uint256 coefficient = (g ** 2 / 1e18) * a;
                uint256 discount = coefficient > 1e34 ? coefficient : 1e34;
                discount = _cubicRoot(discount).mulDivDown(DISCOUNT0, 1e18);

                maxPrice -= maxPrice.mulDivDown(discount, 1e18);
            }
            upper = maxPrice.mulDivDown(token0Upper, 1e18);
            lower = maxPrice.mulDivDown(token0Lower, 1e18);
        }
    }
}
