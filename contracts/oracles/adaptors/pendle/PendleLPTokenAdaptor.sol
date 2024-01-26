// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { BaseOracleAdaptor } from "contracts/oracles/adaptors/BaseOracleAdaptor.sol";

import { PendleLpOracleLib } from "contracts/libraries/external/pendle/PendleLpOracleLib.sol";
import { WAD } from "contracts/libraries/Constants.sol";

import { IOracleRouter } from "contracts/interfaces/IOracleRouter.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IPendlePTOracle } from "contracts/interfaces/external/pendle/IPendlePtOracle.sol";
import { IPMarket, IPPrincipalToken, IStandardizedYield } from "contracts/interfaces/external/pendle/IPMarket.sol";
import { PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";

contract PendleLPTokenAdaptor is BaseOracleAdaptor {
    using PendleLpOracleLib for IPMarket;

    /// TYPES ///

    /// @notice Adaptor storage.
    /// @param twapDuration the twap duration to use when pricing.
    /// @param quoteAsset the asset the twap quote is provided in.
    /// @param pt the address of the Pendle PT associated with LP.
    struct AdaptorData {
        uint32 twapDuration;
        address quoteAsset;
        address pt;
        uint8 quoteAssetDecimals;
    }

    /// CONSTANTS ///

    /// @notice The minimum acceptable twap duration when pricing.
    uint32 public constant MINIMUM_TWAP_DURATION = 12;
    /// @notice Current networks ptOracle.
    /// @dev for mainnet use 0x414d3C8A26157085f286abE3BC6E1bb010733602.
    IPendlePTOracle public immutable ptOracle;

    /// STORAGE ///

    /// @notice Pendle LP adaptor storage.
    mapping(address => AdaptorData) public adaptorData;

    /// EVENTS ///

    event PendleLPAssetAdded(
        address asset,
        AdaptorData assetConfig
    );

    event PendleLPAssetRemoved(address asset);

    /// ERRORS ///

    error PendleLPTokenAdaptor__AssetIsNotSupported();
    error PendleLPTokenAdaptor__WrongMarket();
    error PendleLPTokenAdaptor__WrongQuote();
    error PendleLPTokenAdaptor__TwapDurationIsLessThanMinimum();
    error PendleLPTokenAdaptor__QuoteAssetIsNotSupported();
    error PendleLPTokenAdaptor__CallIncreaseCardinality();
    error PendleLPTokenAdaptor__OldestObservationIsNotSatisfied();
    error PendleLPTokenAdaptor__ConfigurationError();

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        IPendlePTOracle ptOracle_
    ) BaseOracleAdaptor(centralRegistry_) {
        ptOracle = ptOracle_;
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Called during pricing operations.
    /// @param asset The pendle market token being priced.
    /// @param inUSD Indicates whether we want the price in USD or ETH.
    /// @param getLower Since this adaptor calls back into the oracle router
    ///                 it needs to know if it should be working with the upper
    ///                 or lower prices of assets.
    function getPrice(
        address asset,
        bool inUSD,
        bool getLower
    ) external view override returns (PriceReturnData memory pData) {
        AdaptorData memory data = adaptorData[asset];

        if (!isSupportedAsset[asset]) {
            revert PendleLPTokenAdaptor__AssetIsNotSupported();
        }

        uint256 lpRate = IPMarket(asset).getLpToAssetRate(data.twapDuration);
        pData.inUSD = inUSD;

        (uint256 price, uint256 errorCode) = IOracleRouter(
            centralRegistry.oracleRouter()
        ).getPrice(data.quoteAsset, inUSD, getLower);

        if (errorCode > 0) {
            pData.hadError = true;
            return pData;
        }

        // Multiply the quote asset price by the lpRate
        // to get the Lp Token fair value.
        price = (price * lpRate) / WAD;

        if (_checkOracleOverflow(price)) {
            pData.hadError = true;
            return pData;
        }

        pData.price = uint240(price);
    }

    /// @notice Add a Pendle Market as an asset.
    /// @dev Should be called before `OracleRouter:addAssetPriceFeed` is called.
    /// @param asset The address of the Pendle Market.
    /// @param data The adaptor data needed to add `asset`.
    function addAsset(
        address asset,
        AdaptorData memory data
    ) external {
        _checkElevatedPermissions();

        if (isSupportedAsset[asset]) {
            revert PendleLPTokenAdaptor__ConfigurationError();
        }

        // Make sure pt and market match.
        (IStandardizedYield sy, IPPrincipalToken pt, ) = IPMarket(asset)
            .readTokens();

        if (address(pt) != data.pt) {
            revert PendleLPTokenAdaptor__WrongMarket();
        }

        // Make sure quote asset is the same as SY `assetInfo.assetAddress`.
        (, address assetAddress, ) = sy.assetInfo();
        if (assetAddress != data.quoteAsset) {
            revert PendleLPTokenAdaptor__WrongQuote();
        }

        if (data.twapDuration < MINIMUM_TWAP_DURATION) {
            revert PendleLPTokenAdaptor__TwapDurationIsLessThanMinimum();
        }

        // Make sure the underlying PT TWAP is working.
        _checkPtTwap(asset, data.twapDuration);

        if (
            !IOracleRouter(centralRegistry.oracleRouter()).isSupportedAsset(
                data.quoteAsset
            )
        ) {
            revert PendleLPTokenAdaptor__QuoteAssetIsNotSupported();
        }

        // Write to adaptor storage.
        adaptorData[asset] = AdaptorData({
            twapDuration: data.twapDuration,
            quoteAsset: data.quoteAsset,
            pt: data.pt,
            quoteAssetDecimals: data.quoteAssetDecimals
        });
        isSupportedAsset[asset] = true;
        emit PendleLPAssetAdded(asset, data);
    }

    /// @notice Removes a supported asset from the adaptor.
    /// @dev Calls back into oracle router to notify it of its removal.
    /// @param asset The address of the supported asset to remove from
    ///              the adaptor.
    function removeAsset(address asset) external override {
        _checkElevatedPermissions();

        if (!isSupportedAsset[asset]) {
            revert PendleLPTokenAdaptor__AssetIsNotSupported();
        }

        // Notify the adaptor to stop supporting the asset.
        delete isSupportedAsset[asset];

        // Wipe config mapping entries for a gas refund.
        delete adaptorData[asset];

        // Notify the oracle router that we are going to stop supporting
        // the asset.
        IOracleRouter(centralRegistry.oracleRouter()).notifyFeedRemoval(asset);
        emit PendleLPAssetRemoved(asset);
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Check whether the underlying PT TWAP is working.
    /// @param market the address of the Pendle LP.
    /// @param twapDuration the twap duration to use when pricing.
    function _checkPtTwap(address market, uint32 twapDuration) internal view {
        (
            bool increaseCardinalityRequired,
            ,
            bool oldestObservationSatisfied
        ) = ptOracle.getOracleState(market, twapDuration);

        if (increaseCardinalityRequired) {
            revert PendleLPTokenAdaptor__CallIncreaseCardinality();
        }
        if (!oldestObservationSatisfied) {
            revert PendleLPTokenAdaptor__OldestObservationIsNotSatisfied();
        }
    }
}
