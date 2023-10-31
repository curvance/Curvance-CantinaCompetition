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

    /// @notice GMX GM Token Market Data in array
    /// @dev [indexToken, longToken, shortToken]
    mapping(address => address[]) public marketData;

    /// @notice Price unit for token on GMX Reader
    mapping(address => uint256) internal _priceUnit;

    /// ERRORS ///

    error GMAdaptor__ReaderIsZeroAddress();
    error GMAdaptor__DataStoreIsZeroAddress();
    error GMAdaptor__AssetIsAlreadySupported();
    error GMAdaptor__AssetIsNotSupported();
    error GMAdaptor__MarketTokenIsNotSupported(address marketToken);

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
        uint256[] memory marketTokenPrices = new uint256[](3);
        address[] memory marketTokens = marketData[asset];
        uint256 errorCode;
        address marketToken;

        for (uint256 i = 0; i < 3; ++i) {
            marketToken = marketTokens[i];

            (marketTokenPrices[i], errorCode) = priceRouter.getPrice(
                marketToken,
                true,
                false
            );
            if (errorCode > 0) {
                pData.hadError = true;
                return pData;
            }

            marketTokenPrices[i] =
                (marketTokenPrices[i] * 1e30) /
                _priceUnit[marketToken];
        }

        (int256 price, ) = reader.getMarketTokenPrice(
            dataStore,
            IReader.MarketProps(
                asset,
                marketTokens[0],
                marketTokens[1],
                marketTokens[2]
            ),
            IReader.PriceProps(marketTokenPrices[0], marketTokenPrices[0]),
            IReader.PriceProps(marketTokenPrices[1], marketTokenPrices[1]),
            IReader.PriceProps(marketTokenPrices[2], marketTokenPrices[2]),
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
    /// @param asset The address of the token to add pricing for.
    function addAsset(address asset) external onlyElevatedPermissions {
        if (isSupportedAsset[asset]) {
            revert GMAdaptor__AssetIsAlreadySupported();
        }

        IReader.MarketProps memory market = reader.getMarket(dataStore, asset);
        IPriceRouter priceRouter = IPriceRouter(centralRegistry.priceRouter());

        address[] memory marketTokens = new address[](3);
        address marketToken;
        marketTokens[0] = market.indexToken;
        marketTokens[1] = market.longToken;
        marketTokens[2] = market.shortToken;

        for (uint256 i = 0; i < 3; ++i) {
            marketToken = marketTokens[i];

            if (!priceRouter.isSupportedAsset(marketToken)) {
                revert GMAdaptor__MarketTokenIsNotSupported(marketToken);
            }

            if (marketToken == _ARB_BTC) {
                _priceUnit[marketToken] = 1e26;
            } else {
                _priceUnit[marketToken] =
                    1e18 *
                    10 ** IERC20(marketToken).decimals();
            }

            marketData[asset].push(marketToken);
        }

        isSupportedAsset[asset] = true;
    }

    /// @notice Removes a supported asset from the adaptor.
    /// @dev Calls back into price router to notify it of its removal.
    /// @param asset The address of the token to remove.
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
}
