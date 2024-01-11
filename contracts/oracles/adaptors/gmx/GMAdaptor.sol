// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { BaseOracleAdaptor } from "contracts/oracles/adaptors/BaseOracleAdaptor.sol";
import { WAD } from "contracts/libraries/Constants.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";
import { IPriceRouter } from "contracts/interfaces/IPriceRouter.sol";
import { IReader } from "contracts/interfaces/external/gmx/IReader.sol";

contract GMAdaptor is BaseOracleAdaptor {
    /// TYPES ///

    /// @param asset The address of synthetic asset for native token.
    /// @param decimals The decimals of synthetic asset.
    struct SyntheticAsset {
        address asset;
        uint256 decimals;
    }

    /// CONSTANTS ///

    /// keccak256(abi.encode("MAX_PNL_FACTOR_FOR_TRADERS"));
    bytes32 public constant PNL_FACTOR_TYPE =
        0xab15365d3aa743e766355e2557c230d8f943e195dc84d9b2b05928a07b635ee1;

    /// STORAGE ///

    /// @notice GMX Reader address.
    IReader public gmxReader;

    /// @notice GMX DataStore address.
    address public gmxDataStore;

    /// @notice GMX GM Token Market Data in array.
    /// @dev [indexToken, longToken, shortToken].
    mapping(address => address[]) public marketData;

    /// @notice Price unit for token on GMX Reader.
    mapping(address => uint256) internal _priceUnit;

    /// ERRORS ///

    error GMAdaptor__ChainIsNotSupported();
    error GMAdaptor__GMXReaderIsZeroAddress();
    error GMAdaptor__GMXDataStoreIsZeroAddress();
    error GMAdaptor__MarketIsInvalid();
    error GMAdaptor__AssetIsAlreadySupported();
    error GMAdaptor__AssetIsNotSupported();
    error GMAdaptor__MarketTokenIsNotSupported(address token);

    /// CONSTRUCTOR ///

    /// @param centralRegistry_ The address of central registry.
    /// @param gmxReader_ The address of GMX Reader.
    /// @param gmxDataStore_ The address of GMX DataStore.
    constructor(
        ICentralRegistry centralRegistry_,
        address gmxReader_,
        address gmxDataStore_
    ) BaseOracleAdaptor(centralRegistry_) {
        if (block.chainid != 42161) {
            revert GMAdaptor__ChainIsNotSupported();
        }

        _setGMXReader(gmxReader_);
        _setGMXDataStore(gmxDataStore_);
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
        uint256[] memory prices = new uint256[](3);
        address[] memory tokens = marketData[asset];
        uint256 errorCode;
        address token;

        for (uint256 i = 0; i < 3; ++i) {
            token = tokens[i];

            (prices[i], errorCode) = priceRouter.getPrice(token, true, false);
            if (errorCode > 0) {
                pData.hadError = true;
                return pData;
            }

            prices[i] = (prices[i] * 1e30) / _priceUnit[token];
        }

        (int256 price, ) = gmxReader.getMarketTokenPrice(
            gmxDataStore,
            IReader.MarketProps(asset, tokens[0], tokens[1], tokens[2]),
            IReader.PriceProps(prices[0], prices[0]),
            IReader.PriceProps(prices[1], prices[1]),
            IReader.PriceProps(prices[2], prices[2]),
            PNL_FACTOR_TYPE,
            true
        );

        if (price <= 0) {
            pData.hadError = true;
            return pData;
        }

        uint256 newPrice = uint256(price) / 1e12;

        if (_checkOracleOverflow(newPrice)) {
            pData.hadError = true;
            return pData;
        }

        return
            PriceReturnData({
                price: uint240(newPrice),
                hadError: false,
                inUSD: true
            });
    }

    /// @notice Add a GMX GM Token as an asset.
    /// @param asset The address of the token to add pricing for.
    function addAsset(address asset) external {
        _checkElevatedPermissions();

        if (isSupportedAsset[asset]) {
            revert GMAdaptor__AssetIsAlreadySupported();
        }

        IReader.MarketProps memory market = gmxReader.getMarket(
            gmxDataStore,
            asset
        );

        if (
            market.indexToken == address(0) ||
            market.longToken == address(0) ||
            market.shortToken == address(0)
        ) {
            revert GMAdaptor__MarketIsInvalid();
        }

        IPriceRouter priceRouter = IPriceRouter(centralRegistry.priceRouter());

        address[] memory tokens = new address[](3);
        address token;
        tokens[0] = market.indexToken;
        tokens[1] = market.longToken;
        tokens[2] = market.shortToken;

        for (uint256 i = 0; i < 3; ++i) {
            token = tokens[i];

            if (!priceRouter.isSupportedAsset(token)) {
                revert GMAdaptor__MarketTokenIsNotSupported(token);
            }

            if (_priceUnit[token] == 0) {
                _priceUnit[token] = WAD * 10 ** IERC20(token).decimals();
            }

            marketData[asset].push(token);
        }

        isSupportedAsset[asset] = true;
    }

    /// @notice Removes a supported asset from the adaptor.
    /// @dev Calls back into price router to notify it of its removal.
    /// @param asset The address of the token to remove.
    function removeAsset(address asset) external override {
        _checkElevatedPermissions();

        if (!isSupportedAsset[asset]) {
            revert GMAdaptor__AssetIsNotSupported();
        }

        // Notify the adaptor to stop supporting the asset.
        delete isSupportedAsset[asset];

        // Wipe config mapping entries for a gas refund.
        delete marketData[asset];

        // Notify the price router that we are going to
        // stop supporting the asset.
        IPriceRouter(centralRegistry.priceRouter()).notifyFeedRemoval(asset);
    }

    /// @notice Register synthetic assets and decimals.
    /// @param assets The struct array of the synthetic assets to register.
    function registerSyntheticAssets(SyntheticAsset[] memory assets) external {
        _checkElevatedPermissions();

        uint256 numAssets = assets.length;

        for (uint256 i; i < numAssets; ++i) {
            _priceUnit[assets[i].asset] = WAD * 10 ** assets[i].decimals;
        }
    }

    /// @notice Unregister synthetic assets and decimals.
    /// @param assets The struct array of the synthetic assets to unregister.
    function unregisterSyntheticAssets(address[] memory assets) external {
        _checkElevatedPermissions();

        uint256 numAssets = assets.length;

        for (uint256 i; i < numAssets; ++i) {
            _priceUnit[assets[i]] = 0;
        }
    }

    /// @notice Set GMX Reader address.
    function setGMXReader(address newReader) external {
        _checkDaoPermissions();

        _setGMXReader(newReader);
    }

    /// @notice Set GMX DataStore address.
    function setGMXDataStore(address newDataStore) external {
        _checkDaoPermissions();

        _setGMXDataStore(newDataStore);
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Set GMX Reader address.
    function _setGMXReader(address newReader) internal {
        if (newReader == address(0)) {
            revert GMAdaptor__GMXReaderIsZeroAddress();
        }

        gmxReader = IReader(newReader);
    }

    /// @notice Set GMX DataStore address.
    function _setGMXDataStore(address newDataStore) internal {
        if (newDataStore == address(0)) {
            revert GMAdaptor__GMXDataStoreIsZeroAddress();
        }

        gmxDataStore = newDataStore;
    }
}
