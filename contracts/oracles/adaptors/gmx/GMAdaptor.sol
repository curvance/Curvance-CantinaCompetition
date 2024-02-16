// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { BaseOracleAdaptor } from "contracts/oracles/adaptors/BaseOracleAdaptor.sol";
import { WAD } from "contracts/libraries/Constants.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";
import { IOracleRouter } from "contracts/interfaces/IOracleRouter.sol";
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

    /// @dev keccak256(abi.encode("MAX_PNL_FACTOR_FOR_TRADERS"));
    bytes32 public constant PNL_FACTOR_TYPE =
        0xab15365d3aa743e766355e2557c230d8f943e195dc84d9b2b05928a07b635ee1;

    /// STORAGE ///

    /// @notice GMX Reader address.
    IReader public gmxReader;

    /// @notice GMX DataStore address.
    address public gmxDataStore;

    /// @notice GMX GM Token Market Data in array.
    /// @dev [alteredToken, longToken, shortToken, indexToken].
    ///      alteredToken is the address of altered token for synthetic token.
    ///      e.g. WBTC address for BTC.
    mapping(address => address[]) public marketData;

    /// @notice Underlying token address => Denomination for token
    ///         inside the GMX Reader.
    mapping(address => uint256) internal _priceUnit;

    /// EVENTS ///

    event GMXGMAssetAdded(
        address asset,
        address[] marketTokens,
        bool isSynthetic,
        address alteredToken,
        bool isUpdate
    );
    event GMXGMAssetRemoved(address asset);

    /// ERRORS ///

    error GMAdaptor__ChainIsNotSupported();
    error GMAdaptor__GMXReaderIsZeroAddress();
    error GMAdaptor__GMXDataStoreIsZeroAddress();
    error GMAdaptor__MarketIsInvalid();
    error GMAdaptor__AlteredTokenIsInvalid();
    error GMAdaptor__AssetIsNotSupported();
    error GMAdaptor__MarketTokenIsNotSupported(address token);

    /// CONSTRUCTOR ///

    /// @dev Only deployable on Arbitrum.
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

    /// @notice Retrieves the price of a given GMX GM token.
    /// @dev Uses oracles (mostly Chainlink), can price both direct
    ///      and synthetic GM Tokens.
    /// @param asset The address of the asset for which the price is needed.
    /// @return pData A structure containing the price, error status,
    ///               and the quote format of the price.
    function getPrice(
        address asset,
        bool /* inUSD */,
        bool /* getLower */
    ) external view override returns (PriceReturnData memory pData) {
        // Validate we support pricing `asset`.
        if (!isSupportedAsset[asset]) {
            revert GMAdaptor__AssetIsNotSupported();
        }

        // Cache the Oracle Router.
        IOracleRouter oracleRouter = IOracleRouter(
            centralRegistry.oracleRouter()
        );

        uint256[] memory prices = new uint256[](3);
        address[] memory tokens = marketData[asset];
        uint256 errorCode;
        address token;

        // Pull the prices for each underlying (constituent) token
        // making up the GMX GM token.
        for (uint256 i; i < 3; ++i) {
            token = tokens[i];

            (prices[i], errorCode) = oracleRouter.getPrice(token, true, false);
            if (errorCode > 0) {
                pData.hadError = true;
                return pData;
            }

            prices[i] = (prices[i] * 1e30) / _priceUnit[token];
        }

        // Pull token pricing data from gmxReader.
        (int256 price, ) = gmxReader.getMarketTokenPrice(
            gmxDataStore,
            IReader.MarketProps(asset, tokens[3], tokens[1], tokens[2]),
            IReader.PriceProps(prices[0], prices[0]),
            IReader.PriceProps(prices[1], prices[1]),
            IReader.PriceProps(prices[2], prices[2]),
            PNL_FACTOR_TYPE,
            true
        );

        // Make sure we got a positive price, bubble up an error,
        // if we got 0 or a negative number.
        if (price <= 0) {
            pData.hadError = true;
            return pData;
        }

        // Convert from 30 decimals to standardized 18.
        uint256 newPrice = uint256(price) / 1e12;

        // Validate price will not overflow on conversion to uint240.
        if (_checkOracleOverflow(newPrice)) {
            pData.hadError = true;
            return pData;
        }

        pData.inUSD = true;
        pData.price = uint240(newPrice);
    }

    /// @notice Adds pricing support for `asset`, a GMX GM token.
    /// @dev Should be called before `OracleRouter:addAssetPriceFeed`
    ///      is called.
    /// @param asset The address of the GMX GM token to add pricing
    ///              support for.
    /// @param alteredToken The address of the token to use to price
    ///                     a GM token synthetically.
    function addAsset(address asset, address alteredToken) external {
        _checkElevatedPermissions();

        IReader.MarketProps memory market = gmxReader.getMarket(
            gmxDataStore,
            asset
        );
        // Check whether the GM token needs to be synthetically priced.
        bool isSynthetic = market.indexToken.code.length == 0;

        // Validate the market is configured inside gmxReader.
        if (
            market.indexToken == address(0) ||
            market.longToken == address(0) ||
            market.shortToken == address(0)
        ) {
            revert GMAdaptor__MarketIsInvalid();
        }

        // Make sure both `asset` and `alteredToken` parameters
        // are configured properly.
        if (
            (isSynthetic && alteredToken == address(0)) ||
            (!isSynthetic && alteredToken != address(0))
        ) {
            revert GMAdaptor__AlteredTokenIsInvalid();
        }

        IOracleRouter oracleRouter = IOracleRouter(
            centralRegistry.oracleRouter()
        );

        address[] memory tokens = new address[](4);
        tokens[0] = isSynthetic ? alteredToken : market.indexToken;
        tokens[1] = market.longToken;
        tokens[2] = market.shortToken;
        tokens[3] = market.indexToken;

        address token;

        // Configure pricing denomination based on underlying tokens decimals.
        for (uint256 i; i < 3; ++i) {
            token = tokens[i];

            if (!oracleRouter.isSupportedAsset(token)) {
                revert GMAdaptor__MarketTokenIsNotSupported(token);
            }

            if (_priceUnit[token] == 0) {
                _priceUnit[token] = WAD * 10 ** IERC20(token).decimals();
            }
        }

        // Save adaptor data and update mapping that we support `asset` now.
        marketData[asset] = tokens;

        // Check whether this is new or updated support for `asset`.
        bool isUpdate;
        if (isSupportedAsset[asset]) {
            isUpdate = true;
        }

        isSupportedAsset[asset] = true;
        emit GMXGMAssetAdded(
            asset,
            tokens,
            isSynthetic,
            alteredToken,
            isUpdate
        );
    }

    /// @notice Removes a supported asset from the adaptor.
    /// @dev Calls back into Oracle Router to notify it of its removal.
    ///      Requires that `asset` is currently supported.
    /// @param asset The address of the supported asset to remove from
    ///              the adaptor.
    function removeAsset(address asset) external override {
        _checkElevatedPermissions();

        // Validate that `asset` is currently supported.
        if (!isSupportedAsset[asset]) {
            revert GMAdaptor__AssetIsNotSupported();
        }

        // Wipe config mapping entries for a gas refund.
        // Notify the adaptor to stop supporting the asset.
        delete isSupportedAsset[asset];
        delete marketData[asset];

        // Notify the Oracle Router that we are going to
        // stop supporting the asset.
        IOracleRouter(centralRegistry.oracleRouter()).notifyFeedRemoval(asset);
        emit GMXGMAssetRemoved(asset);
    }

    /// @notice Permissioned function to set a new GMX Reader address.
    /// @param newReader The address to set as the new GMX Reader.
    function setGMXReader(address newReader) external {
        _checkDaoPermissions();

        _setGMXReader(newReader);
    }

    /// @notice Permissioned function to set a new GMX DataStore address.
    /// @param newDataStore The address to set as the new GMX DataStore.
    function setGMXDataStore(address newDataStore) external {
        _checkDaoPermissions();

        _setGMXDataStore(newDataStore);
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Helper function to set a new GMX Reader address.
    /// @param newReader The address to set as the new GMX Reader.
    function _setGMXReader(address newReader) internal {
        if (newReader == address(0)) {
            revert GMAdaptor__GMXReaderIsZeroAddress();
        }

        gmxReader = IReader(newReader);
    }

    /// @notice Helper function to set a new GMX DataStore address.
    /// @param newDataStore The address to set as the new GMX DataStore.
    function _setGMXDataStore(address newDataStore) internal {
        if (newDataStore == address(0)) {
            revert GMAdaptor__GMXDataStoreIsZeroAddress();
        }

        gmxDataStore = newDataStore;
    }
}
