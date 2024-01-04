// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { BaseOracleAdaptor } from "contracts/oracles/adaptors/BaseOracleAdaptor.sol";

import { PendlePtOracleLib } from "contracts/libraries/pendle/PendlePtOracleLib.sol";
import { WAD } from "contracts/libraries/Constants.sol";

import { IPriceRouter } from "contracts/interfaces/IPriceRouter.sol";
import { IPMarket, IPPrincipalToken, IStandardizedYield } from "contracts/interfaces/external/pendle/IPMarket.sol";
import { IPendlePTOracle } from "contracts/interfaces/external/pendle/IPendlePtOracle.sol";
import { PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract PendlePrincipalTokenAdaptor is BaseOracleAdaptor {
    using PendlePtOracleLib for IPMarket;

    /// TYPES ///

    /// @notice Adaptor storage
    /// @param market the Pendle market for the Principal Token being priced
    /// @param twapDuration the twap duration to use when pricing
    /// @param quoteAsset the asset the twap quote is provided in
    struct AdaptorData {
        IPMarket market;
        uint32 twapDuration;
        address quoteAsset;
        uint8 quoteAssetDecimals;
    }

    /// CONSTANTS ///

    /// @notice The minimum acceptable twap duration when pricing
    uint32 public constant MINIMUM_TWAP_DURATION = 12;

    /// @notice Current networks ptOracle
    /// @dev for mainnet use 0x414d3C8A26157085f286abE3BC6E1bb010733602
    IPendlePTOracle public immutable ptOracle;

    /// STORAGE ///

    /// @notice Pendle PT adaptor storage
    mapping(address => AdaptorData) public adaptorData;

    /// EVENTS ///

    event PendlePTAssetAdded(
        address asset,
        AdaptorData assetConfig
    );

    event PendlePTAssetRemoved(address asset);

    /// ERRORS ///

    error PendlePrincipalTokenAdaptor__AssetIsNotSupported();
    error PendlePrincipalTokenAdaptor__WrongMarket();
    error PendlePrincipalTokenAdaptor__WrongQuote();
    error PendlePrincipalTokenAdaptor__TwapDurationIsLessThanMinimum();
    error PendlePrincipalTokenAdaptor__CallIncreaseCardinality();
    error PendlePrincipalTokenAdaptor__OldestObservationIsNotSatisfied();
    error PendlePrincipalTokenAdaptor__QuoteAssetIsNotSupported();
    error PendlePrincipalTokenAdaptor__ConfigurationError();

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        IPendlePTOracle ptOracle_
    ) BaseOracleAdaptor(centralRegistry_) {
        ptOracle = ptOracle_;
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Called during pricing operations.
    /// @param asset the pendle principal token being priced
    /// @param inUSD indicates whether we want the price in USD or ETH
    /// @param getLower Since this adaptor calls back into the price router
    ///                 it needs to know if it should be working with the upper
    ///                 or lower prices of assets
    function getPrice(
        address asset,
        bool inUSD,
        bool getLower
    ) external view override returns (PriceReturnData memory pData) {
        if (!isSupportedAsset[asset]) {
            revert PendlePrincipalTokenAdaptor__AssetIsNotSupported();
        }

        AdaptorData memory data = adaptorData[asset];
        pData.inUSD = inUSD;
        uint256 ptRate = data.market.getPtToAssetRate(data.twapDuration);

        (uint256 price, uint256 errorCode) = IPriceRouter(
            centralRegistry.priceRouter()
        ).getPrice(data.quoteAsset, inUSD, getLower);

        if (errorCode > 0) {
            pData.hadError = true;
            return pData;
        }

        // Multiply the quote asset price by the ptRate
        // to get the Principal Token fair value.
        price = (price * ptRate) / WAD;

        if (_checkOracleOverflow(price)) {
            pData.hadError = true;
            return pData;
        }

        // Multiply the quote asset price by the ptRate
        // to get the Principal Token fair value.
        pData.price = uint240(price);
    }

    /// @notice Add a Pendle Principal Token as an asset.
    /// @dev Should be called before `PriceRotuer:addAssetPriceFeed` is called.
    /// @param asset the address of the Pendle PT
    /// @param data the adaptor data needed to add `asset`
    function addAsset(
        address asset,
        AdaptorData memory data
    ) external {
        _checkElevatedPermissions();

        if (isSupportedAsset[asset]) {
            revert PendlePrincipalTokenAdaptor__ConfigurationError();
        }

        // Make sure pt and market match.
        (IStandardizedYield sy, IPPrincipalToken pt, ) = data
            .market
            .readTokens();

        if (address(pt) != asset) {
            revert PendlePrincipalTokenAdaptor__WrongMarket();
        }

        // Make sure quote asset is the same as SY `assetInfo.assetAddress`
        (, address assetAddress, ) = sy.assetInfo();
        if (assetAddress != data.quoteAsset) {
            revert PendlePrincipalTokenAdaptor__WrongQuote();
        }

        if (data.twapDuration < MINIMUM_TWAP_DURATION) {
            revert PendlePrincipalTokenAdaptor__TwapDurationIsLessThanMinimum();
        }

        (
            bool increaseCardinalityRequired,
            ,
            bool oldestObservationSatisfied
        ) = ptOracle.getOracleState(address(data.market), data.twapDuration);

        if (increaseCardinalityRequired) {
            revert PendlePrincipalTokenAdaptor__CallIncreaseCardinality();
        }
        if (!oldestObservationSatisfied) {
            revert PendlePrincipalTokenAdaptor__OldestObservationIsNotSatisfied();
        }
        if (
            !IPriceRouter(centralRegistry.priceRouter()).isSupportedAsset(
                data.quoteAsset
            )
        ) {
            revert PendlePrincipalTokenAdaptor__QuoteAssetIsNotSupported();
        }

        // Write to extension storage.
        adaptorData[asset] = AdaptorData({
            market: data.market,
            twapDuration: data.twapDuration,
            quoteAsset: data.quoteAsset,
            quoteAssetDecimals: data.quoteAssetDecimals
        });

        isSupportedAsset[asset] = true;
        emit PendlePTAssetAdded(asset, data);
    }

    /// @notice Removes a supported asset from the adaptor.
    /// @dev Calls back into price router to notify it of its removal
    /// @param asset The address of the asset to be removed.
    function removeAsset(address asset) external override {
        _checkElevatedPermissions();

        if (!isSupportedAsset[asset]) {
            revert PendlePrincipalTokenAdaptor__AssetIsNotSupported();
        }

        // Notify the adaptor to stop supporting the asset
        delete isSupportedAsset[asset];

        // Wipe config mapping entries for a gas refund
        delete adaptorData[asset];

        ///Notify the price router that we are going to stop supporting the asset
        IPriceRouter(centralRegistry.priceRouter()).notifyFeedRemoval(asset);
        emit PendlePTAssetRemoved(asset);
    }
}
