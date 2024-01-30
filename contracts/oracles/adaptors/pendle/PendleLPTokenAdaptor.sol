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
    /// @notice Current network's ptOracle.
    /// @dev for mainnet use 0x414d3C8A26157085f286abE3BC6E1bb010733602.
    IPendlePTOracle public immutable ptOracle;

    /// STORAGE ///

    /// @notice Pendle lp token address => AdaptorData.
    mapping(address => AdaptorData) public adaptorData;

    /// EVENTS ///

    event PendleLPAssetAdded(
        address asset,
        AdaptorData assetConfig,
        bool isUpdate
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

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        IPendlePTOracle ptOracle_
    ) BaseOracleAdaptor(centralRegistry_) {
        ptOracle = ptOracle_;
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Retrieves the price of a given Pendle lp token.
    /// @dev Price is returned in USD or ETH depending on 'inUSD' parameter.
    /// @param asset The address of the asset for which the price is needed.
    /// @param inUSD A boolean to determine if the price should be returned in
    ///              USD or not.
    /// @param getLower A boolean to determine if lower of two oracle prices
    ///                 should be retrieved.
    /// @return pData A structure containing the price, error status,
    ///                         and the quote format of the price.
    function getPrice(
        address asset,
        bool inUSD,
        bool getLower
    ) external view override returns (PriceReturnData memory pData) {
        // Validate we support pricing `asset`.
        if (!isSupportedAsset[asset]) {
            revert PendleLPTokenAdaptor__AssetIsNotSupported();
        }

        AdaptorData memory data = adaptorData[asset];
        // Get LP to underlying asset ratio conversion.
        uint256 lpRate = IPMarket(asset).getLpToAssetRate(data.twapDuration);
        
        (uint256 price, uint256 errorCode) = IOracleRouter(
            centralRegistry.oracleRouter()
        ).getPrice(data.quoteAsset, inUSD, getLower);

        // Validate we did not run into any errors pricing the quote asset.
        if (errorCode > 0) {
            pData.hadError = true;
            return pData;
        }

        // Multiply the quote asset price by the lpRate
        // to get the Lp Token fair value.
        price = (price * lpRate) / WAD;

        // Validate price will not overflow on conversion to uint240.
        if (_checkOracleOverflow(price)) {
            pData.hadError = true;
            return pData;
        }

        pData.inUSD = inUSD;
        pData.price = uint240(price);
    }

    /// @notice Adds pricing support for `asset`, a pendle lp token.
    /// @dev Should be called before `OracleRouter:addAssetPriceFeed`
    ///      is called.
    /// @param asset The address of the Pendle lp token market.
    /// @param data The adaptor data needed to add `asset`.
    function addAsset(
        address asset,
        AdaptorData memory data
    ) external {
        _checkElevatedPermissions();

        // Make sure pt and market match.
        (IStandardizedYield sy, IPPrincipalToken pt, ) = IPMarket(asset)
            .readTokens();

        // Validate pt pulled from market matches pt inside `data`.
        if (address(pt) != data.pt) {
            revert PendleLPTokenAdaptor__WrongMarket();
        }

        // Validate the parameter twap duration is within acceptable bounds.
        if (data.twapDuration < MINIMUM_TWAP_DURATION) {
            revert PendleLPTokenAdaptor__TwapDurationIsLessThanMinimum();
        }

        // Make sure quote asset is the same as SY `assetInfo.assetAddress`.
        (, address assetAddress, ) = sy.assetInfo();
        if (assetAddress != data.quoteAsset) {
            revert PendleLPTokenAdaptor__WrongQuote();
        }

        // Make sure the underlying PT TWAP is working.
        _checkPtTwap(asset, data.twapDuration);

        // Validate we support the pricing quote asset for this LP token.
        if (
            !IOracleRouter(centralRegistry.oracleRouter()).isSupportedAsset(
                data.quoteAsset
            )
        ) {
            revert PendleLPTokenAdaptor__QuoteAssetIsNotSupported();
        }

        // Save adaptor data and update mapping that we support `asset` now.
        adaptorData[asset] = data;

        // Check whether this is new or updated support for `asset`.
        bool isUpdate;
        if (isSupportedAsset[asset]) {
            isUpdate = true;
        }

        isSupportedAsset[asset] = true;
        emit PendleLPAssetAdded(asset, data, isUpdate);
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
            revert PendleLPTokenAdaptor__AssetIsNotSupported();
        }

        // Wipe config mapping entries for a gas refund.
        // Notify the adaptor to stop supporting the asset.
        delete isSupportedAsset[asset];
        delete adaptorData[asset];

        // Notify the Oracle Router that we are going to stop supporting
        // the asset.
        IOracleRouter(centralRegistry.oracleRouter()).notifyFeedRemoval(asset);
        emit PendleLPAssetRemoved(asset);
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Helper function to check whether the underlying PT TWAP
    ///         is working.
    /// @param market The address of the Pendle LP.
    /// @param twapDuration The twap duration to use when pricing.
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
