// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { BaseOracleAdaptor } from "contracts/oracles/adaptors/BaseOracleAdaptor.sol";
import { ERC20 } from "contracts/libraries/external/ERC20.sol";

import { IOracleRouter } from "contracts/interfaces/IOracleRouter.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";
import { IStaticOracle } from "contracts/interfaces/external/uniswap/IStaticOracle.sol";
import { UniswapV3Pool } from "contracts/interfaces/external/uniswap/UniswapV3Pool.sol";

contract UniswapV3Adaptor is BaseOracleAdaptor {
    /// TYPES ///

    /// @notice Stores configuration data for Uniswap V3 Twap price sources.
    /// @param priceSource The address location where you query
    ///                    the associated assets TWAP price.
    /// @param secondsAgo Period used for TWAP calculation.
    /// @param baseDecimals The decimals of base asset you want to price.
    /// @param quoteDecimals The decimals asset price is quoted in.
    /// @param quoteToken The asset Twap calulation denominates in.
    struct AdaptorData {
        address priceSource;
        uint32 secondsAgo;
        uint8 baseDecimals;
        uint8 quoteDecimals;
        address quoteToken;
    }

    /// CONSTANTS ///

    /// @notice The smallest possible TWAP that can be used.
    ///         300 = 5 minutes.
    uint32 public constant MINIMUM_SECONDS_AGO = 300;

    /// @notice Chain WETH address.
    address public immutable WETH;

    /// @notice Static uniswap oracle router address.
    IStaticOracle public immutable uniswapOracleRouter;

    /// STORAGE ///

    /// @notice Asset Address => AdaptorData.
    mapping(address => AdaptorData) public adaptorData;

    /// EVENTS ///

    event UniswapV3AssetAdded(address asset, AdaptorData assetConfig);
    event UniswapV3AssetRemoved(address asset);

    /// ERRORS ///

    error UniswapV3Adaptor__AssetIsNotSupported();
    error UniswapV3Adaptor__SecondsAgoIsLessThanMinimum();

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        IStaticOracle oracleAddress_,
        address WETH_
    ) BaseOracleAdaptor(centralRegistry_) {
        uniswapOracleRouter = oracleAddress_;
        WETH = WETH_;
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Gets the price of a given asset.
    /// @dev This function uses the Uniswap V3 oracle to calculate the price.
    /// @param asset The address of the asset for which the price is needed.
    /// @param inUSD A boolean to determine if the price should be returned
    ///              in USD or ETH.
    /// @param getLower A boolean to determine if lower of two oracle prices
    ///                 should be retrieved.
    /// @return pData A structure containing the price, error status,
    ///               and the quote format of the price.
    function getPrice(
        address asset,
        bool inUSD,
        bool getLower
    ) external view override returns (PriceReturnData memory pData) {
        // Validate we support pricing `asset`.
        if (!isSupportedAsset[asset]) {
            revert UniswapV3Adaptor__AssetIsNotSupported();
        }

        AdaptorData memory data = adaptorData[asset];
        
        address[] memory pools = new address[](1);
        pools[0] = data.priceSource;
        uint256 twapPrice;
        pData.inUSD = inUSD;

        (bool success, bytes memory returnData) = address(uniswapOracleRouter)
            .staticcall(
                abi.encodePacked(
                    uniswapOracleRouter
                        .quoteSpecificPoolsWithTimePeriod
                        .selector,
                    abi.encode(
                        10 ** data.baseDecimals,
                        asset,
                        data.quoteToken,
                        pools,
                        data.secondsAgo
                    )
                )
            );

        if (success) {
            twapPrice = abi.decode(returnData, (uint256));
        } else {
            // Uniswap TWAP check reverted, notify the oracle router
            // that we had an error
            pData.hadError = true;
            return pData;
        }

        IOracleRouter OracleRouter = IOracleRouter(centralRegistry.oracleRouter());

        // We want the asset price in USD which uniswap cant do,
        // so find out the price of the quote token in USD then divide
        // so its in USD
        if (inUSD) {
            if (!OracleRouter.isSupportedAsset(data.quoteToken)) {
                // Our oracle router does not know how to value this quote token
                // so we cant use the TWAP data
                pData.hadError = true;
                return pData;
            }

            (uint256 quoteTokenDenominator, uint256 errorCode) = OracleRouter
                .getPrice(data.quoteToken, true, getLower);

            // Make sure that if the Price Router had an error,
            // it was not catastrophic
            if (errorCode > 1) {
                pData.hadError = true;
                return pData;
            }

            // We have a route to USD pricing so we can convert
            // the quote token price to USD and return.
            uint256 newPrice = (twapPrice * quoteTokenDenominator) /
                (10 ** data.quoteDecimals);

            if (_checkOracleOverflow(newPrice)) {
                pData.hadError = true;
                return pData;
            }

            pData.price = uint240(newPrice);
            return pData;
        }

        if (data.quoteToken != WETH) {
            if (!OracleRouter.isSupportedAsset(data.quoteToken)) {
                // Our oracle router does not know how to value this quote
                // token so we cant use the TWAP data.
                pData.hadError = true;
                return pData;
            }

            (uint256 quoteTokenDenominator, uint256 errorCode) = OracleRouter
                .getPrice(data.quoteToken, false, getLower);

            // Make sure that if the Price Router had an error,
            // it was not catastrophic.
            if (errorCode > 1) {
                pData.hadError = true;
                return pData;
            }

            twapPrice = twapPrice / quoteTokenDenominator;

            if (_checkOracleOverflow(twapPrice)) {
                pData.hadError = true;
                return pData;
            }

            // We have a route to ETH pricing so we can convert
            // the quote token price to ETH and return.
            pData.price = uint240(twapPrice);
            return pData;
        }

        if (_checkOracleOverflow(twapPrice)) {
            pData.hadError = true;
            return pData;
        }

        pData.price = uint240(twapPrice);
    }

    function addAsset(address asset, AdaptorData memory data) external {
        _checkElevatedPermissions();

        // Verify seconds ago is reasonable.
        if (data.secondsAgo < MINIMUM_SECONDS_AGO) {
            revert UniswapV3Adaptor__SecondsAgoIsLessThanMinimum();
        }

        UniswapV3Pool pool = UniswapV3Pool(data.priceSource);

        address token0 = pool.token0();
        address token1 = pool.token1();
        if (token0 == asset) {
            data.baseDecimals = ERC20(asset).decimals();
            data.quoteDecimals = ERC20(token1).decimals();
            data.quoteToken = token1;
        } else if (token1 == asset) {
            data.baseDecimals = ERC20(asset).decimals();
            data.quoteDecimals = ERC20(token0).decimals();
            data.quoteToken = token0;
        } else revert UniswapV3Adaptor__AssetIsNotSupported();

        adaptorData[asset] = data;
        isSupportedAsset[asset] = true;
        emit UniswapV3AssetAdded(asset, data);
    }

    /// @notice Removes a supported asset from the adaptor.
    /// @dev Calls back into oracle router to notify it of its removal.
    ///      Requires that `asset` is currently supported.
    /// @param asset The address of the supported asset to remove from
    ///              the adaptor.
    function removeAsset(address asset) external override {
        _checkElevatedPermissions();

        // Validate that `asset` is currently supported.
        if (!isSupportedAsset[asset]) {
            revert UniswapV3Adaptor__AssetIsNotSupported();
        }

        // Notify the adaptor to stop supporting the asset
        delete isSupportedAsset[asset];

        // Wipe config mapping entries for a gas refund
        delete adaptorData[asset];

        // Notify the oracle router that we are going
        // to stop supporting the asset
        IOracleRouter(centralRegistry.oracleRouter()).notifyFeedRemoval(asset);
        emit UniswapV3AssetRemoved(asset);
    }
}
