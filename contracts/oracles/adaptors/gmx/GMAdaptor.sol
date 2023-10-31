// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { BaseOracleAdaptor } from "contracts/oracles/adaptors/BaseOracleAdaptor.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";
import { IPriceRouter } from "contracts/interfaces/IPriceRouter.sol";
import { IReader } from "contracts/interfaces/external/gmx/IReader.sol";

contract GMAdaptor is BaseOracleAdaptor {
    /// CONSTANTS ///

    address internal constant _ARB_BTC =
        0x47904963fc8b2340414262125aF798B9655E58Cd;

    /// @notice keccak256(abi.encode("MAX_PNL_FACTOR_FOR_TRADERS"));
    bytes32 public constant PNL_FACTOR_TYPE =
        0xab15365d3aa743e766355e2557c230d8f943e195dc84d9b2b05928a07b635ee1;

    /// @notice GMX Reader address
    IReader public immutable reader;

    /// @notice GMX DataStore address
    address public immutable dataStore;

    /// STORAGE ///

    /// @notice GMX GM Token Market Data
    mapping(address => IReader.MarketProps) public marketData;

    /// @notice Price unit for token on GMX Reader
    mapping(address => uint256) internal _priceUnit;

    /// ERRORS ///

    error GMAdaptor__ReaderIsZeroAddress();
    error GMAdaptor__DataStoreIsZeroAddress();
    error GMAdaptor__AssetIsAlreadySupported();
    error GMAdaptor__AssetIsNotSupported();
    error GMAdaptor__ConfigurationError();

    /// CONSTRUCTOR ///

    /// @param centralRegistry_ The address of central registry.
    /// @param reader_ The address of GMX Reader.
    /// @param dataStore_ The address of GMX DataStore.
    constructor(
        ICentralRegistry centralRegistry_,
        address reader_,
        address dataStore_
    ) BaseOracleAdaptor(centralRegistry_) {
        if (reader_ == address(0)) {
            revert GMAdaptor__ReaderIsZeroAddress();
        }
        if (dataStore_ == address(0)) {
            revert GMAdaptor__DataStoreIsZeroAddress();
        }

        reader = IReader(reader_);
        dataStore = dataStore_;
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Retrieves the price of a given asset.
    /// @dev Uses Chainlink oracles to fetch the price data.
    ///      Price is returned in USD or ETH depending on 'inUSD' parameter.
    /// @param asset The address of the asset for which the price is needed.
    /// @return pData A structure containing the price, error status,
    ///               and the quote format of the price.
    function getPrice(
        address asset,
        bool,
        bool
    ) external view override returns (PriceReturnData memory pData) {
        if (!isSupportedAsset[asset]) {
            revert GMAdaptor__AssetIsNotSupported();
        }

        IPriceRouter priceRouter = IPriceRouter(centralRegistry.priceRouter());
        uint256 indexTokenPrice;
        uint256 longTokenPrice;
        uint256 shortTokenPrice;
        uint256 errorCode;

        (indexTokenPrice, errorCode) = priceRouter.getPrice(
            marketData[asset].indexToken,
            true,
            false
        );
        if (errorCode > 0) {
            pData.hadError = true;
            return pData;
        }

        (longTokenPrice, errorCode) = priceRouter.getPrice(
            marketData[asset].longToken,
            true,
            false
        );
        if (errorCode > 0) {
            pData.hadError = true;
            return pData;
        }

        (shortTokenPrice, errorCode) = priceRouter.getPrice(
            marketData[asset].shortToken,
            true,
            false
        );
        if (errorCode > 0) {
            pData.hadError = true;
            return pData;
        }
        indexTokenPrice =
            (indexTokenPrice * 1e30) /
            _priceUnit[marketData[asset].indexToken];
        longTokenPrice =
            (longTokenPrice * 1e30) /
            _priceUnit[marketData[asset].longToken];
        shortTokenPrice =
            (shortTokenPrice * 1e30) /
            _priceUnit[marketData[asset].shortToken];

        (int256 price, ) = reader.getMarketTokenPrice(
            dataStore,
            marketData[asset],
            IReader.PriceProps(indexTokenPrice, indexTokenPrice),
            IReader.PriceProps(longTokenPrice, longTokenPrice),
            IReader.PriceProps(shortTokenPrice, shortTokenPrice),
            PNL_FACTOR_TYPE,
            true
        );

        if (price < 0) {
            pData.hadError = true;
            return pData;
        }

        return
            PriceReturnData({
                price: uint240(uint256(price) / 1e12),
                hadError: false,
                inUSD: true
            });
    }

    /// @notice Add a GMX GM Token as an asset.
    /// @param asset The address of the token to add pricing for
    function addAsset(address asset) external onlyElevatedPermissions {
        if (isSupportedAsset[asset]) {
            revert GMAdaptor__AssetIsAlreadySupported();
        }

        IReader.MarketProps memory market = reader.getMarket(dataStore, asset);
        IPriceRouter priceRouter = IPriceRouter(centralRegistry.priceRouter());

        if (!priceRouter.isSupportedAsset(market.indexToken)) {
            revert GMAdaptor__ConfigurationError();
        }
        if (!priceRouter.isSupportedAsset(market.longToken)) {
            revert GMAdaptor__ConfigurationError();
        }
        if (!priceRouter.isSupportedAsset(market.shortToken)) {
            revert GMAdaptor__ConfigurationError();
        }

        if (market.indexToken == _ARB_BTC) {
            _priceUnit[market.indexToken] = 1e26;
        } else {
            _priceUnit[market.indexToken] =
                1e18 *
                10 ** IERC20(market.indexToken).decimals();
        }
        if (market.longToken == _ARB_BTC) {
            _priceUnit[market.longToken] = 1e26;
        } else {
            _priceUnit[market.longToken] =
                1e18 *
                10 ** IERC20(market.longToken).decimals();
        }
        if (market.shortToken == _ARB_BTC) {
            _priceUnit[market.shortToken] = 1e26;
        } else {
            _priceUnit[market.shortToken] =
                1e18 *
                10 ** IERC20(market.shortToken).decimals();
        }

        marketData[asset] = market;
        isSupportedAsset[asset] = true;
    }

    /// @notice Removes a supported asset from the adaptor.
    /// @dev Calls back into price router to notify it of its removal
    function removeAsset(address asset) external override onlyDaoPermissions {
        if (!isSupportedAsset[asset]) {
            revert GMAdaptor__AssetIsNotSupported();
        }

        // Notify the adaptor to stop supporting the asset
        delete isSupportedAsset[asset];

        // Wipe config mapping entries for a gas refund
        delete marketData[asset];

        // Notify the price router that we are going to stop supporting the asset
        IPriceRouter(centralRegistry.priceRouter()).notifyFeedRemoval(asset);
    }

    /// INTERNAL FUNCTIONS ///
}
