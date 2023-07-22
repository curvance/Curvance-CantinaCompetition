// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import { BaseOracleAdaptor } from "contracts/oracles/adaptors/BaseOracleAdaptor.sol";
import { ERC20 } from "contracts/libraries/ERC20.sol";

import { IPriceRouter } from "contracts/interfaces/IPriceRouter.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IOracleAdaptor, PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";
import { IStaticOracle } from "contracts/interfaces/external/uniswap/IStaticOracle.sol";
import { UniswapV3Pool } from "contracts/interfaces/external/uniswap/UniswapV3Pool.sol";

contract UniswapV3Adaptor is BaseOracleAdaptor {
    /// @notice Stores configuration data for Uniswap V3 Twap price sources.
    /// @param priceSource The address location where you query the associated assets TWAP price
    /// @param secondsAgo period used for TWAP calculation
    /// @param baseDecimals the asset you want to price, decimals
    /// @param quoteDecimals the asset price is quoted in, decimals
    /// @param baseToken the asset you want to price
    /// @param quoteToken the asset Twap calulation denominates in
    struct AdaptorData {
        address priceSource;
        uint32 secondsAgo;
        uint8 baseDecimals;
        uint8 quoteDecimals;
        address baseToken;
        address quoteToken;
    }

    /// @notice Uniswap adaptor storage
    mapping(address => AdaptorData) public adaptorData;

    /// @notice Chain WETH address.
    address public immutable WETH;

    IStaticOracle public immutable uniswapOracleRouter;

    /// @notice The smallest possible TWAP that can be used.
    uint32 public constant MINIMUM_SECONDS_AGO = 300;

    /// @notice Token amount to check uniswap twap price against
    uint128 public constant ORACLE_PRECISION = 1e18;

    constructor(
        ICentralRegistry centralRegistry_,
        IStaticOracle oracleAddress_,
        address WETH_
    ) BaseOracleAdaptor(centralRegistry_) {
        uniswapOracleRouter = oracleAddress_;
        WETH = WETH_;
    }

    /// @notice Gets the price of a given asset.
    /// @dev This function uses the Uniswap V3 oracle to calculate the price.
    /// @param asset The address of the asset for which the price is needed.
    /// @param isUsd A boolean to determine if the price should be returned in USD or ETH.
    /// @param getLower A boolean to determine if lower of two oracle prices should be retrieved.
    /// @return PriceReturnData A structure containing the price, error status, and the quote format of the price.
    function getPrice(
        address asset,
        bool isUsd,
        bool getLower
    ) external view override returns (PriceReturnData memory) {
        require(
            isSupportedAsset[asset],
            "UniswapV3Adaptor: asset not supported"
        );

        AdaptorData memory uniswapFeed = adaptorData[asset];
        address[] memory pools = new address[](1);
        pools[0] = uniswapFeed.priceSource;
        uint256 twapPrice;

        (bool success, bytes memory returnData) = address(uniswapOracleRouter)
            .staticcall(
                abi.encodePacked(
                    uniswapOracleRouter
                        .quoteSpecificPoolsWithTimePeriod
                        .selector,
                    abi.encode(
                        ORACLE_PRECISION,
                        uniswapFeed.baseToken,
                        uniswapFeed.quoteToken,
                        pools,
                        uniswapFeed.secondsAgo
                    )
                )
            );

        if (success) {
            twapPrice = abi.decode(returnData, (uint256));
        } else {
            /// Uniswap TWAP check reverted, notify the price router that we had an error
            return PriceReturnData({ price: 0, hadError: true, inUSD: isUsd });
        }

        IPriceRouter PriceRouter = IPriceRouter(centralRegistry.priceRouter());

        /// We want the asset price in USD which uniswap cant do, so find out the price of the quote token in USD then divide so its in USD
        if (isUsd) {
            if (!PriceRouter.isSupportedAsset(uniswapFeed.quoteToken)) {
                /// Our price router does not know how to value this quote token so we cant use the TWAP data
                return
                    PriceReturnData({
                        price: 0,
                        hadError: true,
                        inUSD: isUsd
                    });
            }

            (uint256 quoteTokenDenominator, uint256 errorCode) = PriceRouter
                .getPrice(uniswapFeed.quoteToken, true, getLower);

            /// Make sure that if the Price Router had an error, it was not catastrophic
            if (errorCode > 1) {
                return
                    PriceReturnData({
                        price: 0,
                        hadError: true,
                        inUSD: isUsd
                    });
            }

            /// We have a route to USD pricing so we can convert the quote token price to USD and return
            return
                PriceReturnData({
                    price: uint240(twapPrice / quoteTokenDenominator),
                    hadError: false,
                    inUSD: true
                });
        }

        if (uniswapFeed.quoteToken != WETH) {
            if (!PriceRouter.isSupportedAsset(uniswapFeed.quoteToken)) {
                /// Our price router does not know how to value this quote token so we cant use the TWAP data
                return
                    PriceReturnData({
                        price: 0,
                        hadError: true,
                        inUSD: isUsd
                    });
            }

            (uint256 quoteTokenDenominator, uint256 errorCode) = PriceRouter
                .getPrice(uniswapFeed.quoteToken, false, getLower);

            /// Make sure that if the Price Router had an error, it was not catastrophic
            if (errorCode > 1) {
                return
                    PriceReturnData({
                        price: 0,
                        hadError: true,
                        inUSD: isUsd
                    });
            }

            /// We have a route to ETH pricing so we can convert the quote token price to ETH and return
            return
                PriceReturnData({
                    price: uint240(twapPrice / quoteTokenDenominator),
                    hadError: false,
                    inUSD: false
                });
        }

        return
            PriceReturnData({
                price: uint240(twapPrice),
                hadError: false,
                inUSD: false
            });
    }

    function addAsset(
        address asset,
        AdaptorData memory parameters
    ) external onlyElevatedPermissions {
        /// Verify seconds ago is reasonable.
        require(
            parameters.secondsAgo >= MINIMUM_SECONDS_AGO,
            "UniswapV3Adaptor: seconds ago parameter too small"
        );

        UniswapV3Pool pool = UniswapV3Pool(parameters.priceSource);

        address token0 = pool.token0();
        address token1 = pool.token1();
        if (token0 == asset) {
            parameters.baseDecimals = ERC20(asset).decimals();
            parameters.quoteDecimals = ERC20(token1).decimals();
            parameters.quoteToken = token1;
        } else if (token1 == asset) {
            parameters.baseDecimals = ERC20(asset).decimals();
            parameters.quoteDecimals = ERC20(token0).decimals();
            parameters.quoteToken = token0;
        } else revert("UniswapV3Adaptor: twap asset not in pool");

        adaptorData[asset] = parameters;

        isSupportedAsset[asset] = true;
    }

    /// @notice Removes a supported asset from the adaptor.
    /// @dev Calls back into price router to notify it of its removal
    /// @param asset The address of the asset to be removed.
    function removeAsset(address asset) external override onlyDaoPermissions {
        require(
            isSupportedAsset[asset],
            "UniswapV3Adaptor: asset not supported"
        );

        /// Notify the adaptor to stop supporting the asset
        delete isSupportedAsset[asset];

        /// Wipe config mapping entries for a gas refund
        delete adaptorData[asset];

        /// Notify the price router that we are going to stop supporting the asset
        IPriceRouter(centralRegistry.priceRouter())
            .notifyAssetPriceFeedRemoval(asset);
    }
}
