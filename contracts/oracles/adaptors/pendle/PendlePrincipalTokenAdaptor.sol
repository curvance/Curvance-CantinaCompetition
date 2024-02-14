// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { BaseOracleAdaptor } from "contracts/oracles/adaptors/BaseOracleAdaptor.sol";

import { PendlePtOracleLib } from "contracts/libraries/external/pendle/PendlePtOracleLib.sol";
import { WAD } from "contracts/libraries/Constants.sol";

import { IOracleRouter } from "contracts/interfaces/IOracleRouter.sol";
import { IPMarket, IPPrincipalToken, IStandardizedYield } from "contracts/interfaces/external/pendle/IPMarket.sol";
import { IPendlePTOracle } from "contracts/interfaces/external/pendle/IPendlePtOracle.sol";
import { PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract PendlePrincipalTokenAdaptor is BaseOracleAdaptor {
    using PendlePtOracleLib for IPMarket;

    /// TYPES ///

    /// @notice Adaptor storage.
    /// @param market the Pendle market for the Principal Token being priced.
    /// @param twapDuration the twap duration to use when pricing.
    /// @param quoteAsset the asset the twap quote is provided in.
    struct AdaptorData {
        IPMarket market;
        uint32 twapDuration;
        address quoteAsset;
        uint8 quoteAssetDecimals;
    }

    /// CONSTANTS ///

    /// @notice The minimum acceptable twap duration when pricing.
    uint32 public constant MINIMUM_TWAP_DURATION = 12;

    /// @notice Current networks ptOracle.
    /// @dev for mainnet use 0x414d3C8A26157085f286abE3BC6E1bb010733602.
    IPendlePTOracle public immutable ptOracle;

    /// STORAGE ///

    /// @notice Pendle PT address => AdaptorData.
    mapping(address => AdaptorData) public adaptorData;

    /// EVENTS ///

    event PendlePTAssetAdded(
        address asset,
        AdaptorData assetConfig,
        bool isUpdate
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

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        IPendlePTOracle ptOracle_
    ) BaseOracleAdaptor(centralRegistry_) {
        ptOracle = ptOracle_;
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Retrieves the price of a given Pendle pt.
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
            revert PendlePrincipalTokenAdaptor__AssetIsNotSupported();
        }

        AdaptorData memory data = adaptorData[asset];
        // Get PT to underlying asset ratio conversion.
        uint256 ptRate = data.market.getPtToAssetRate(data.twapDuration);

        (uint256 price, uint256 errorCode) = IOracleRouter(
            centralRegistry.oracleRouter()
        ).getPrice(data.quoteAsset, inUSD, getLower);

        // Validate we did not run into any errors pricing the quote asset.
        if (errorCode > 0) {
            pData.hadError = true;
            return pData;
        }

        // Multiply the quote asset price by the ptRate
        // to get the Principal Token fair value.
        price = (price * ptRate) / WAD;

        // Validate price will not overflow on conversion to uint240.
        if (_checkOracleOverflow(price)) {
            pData.hadError = true;
            return pData;
        }

        pData.inUSD = inUSD;
        pData.price = uint240(price);
    }

    /// @notice Adds pricing support for `asset`, a Pendle principal token.
    /// @dev Should be called before `OracleRouter:addAssetPriceFeed`
    ///      is called.
    /// @param asset The address of the Pendle principal token to add pricing
    ///              support for.
    /// @param data The adaptor data needed to add `asset`.
    function addAsset(
        address asset,
        AdaptorData memory data
    ) external {
        _checkElevatedPermissions();

        // Make sure pt and market match.
        (IStandardizedYield sy, IPPrincipalToken pt, ) = data
            .market
            .readTokens();

        // Validate pt pulled from market matches `asset`.
        if (address(pt) != asset) {
            revert PendlePrincipalTokenAdaptor__WrongMarket();
        }

        // Validate the parameter twap duration is within acceptable bounds.
        if (data.twapDuration < MINIMUM_TWAP_DURATION) {
            revert PendlePrincipalTokenAdaptor__TwapDurationIsLessThanMinimum();
        }

        // Make sure quote asset is the same as SY `assetInfo.assetAddress`.
        (, address assetAddress, ) = sy.assetInfo();
        if (assetAddress != data.quoteAsset) {
            revert PendlePrincipalTokenAdaptor__WrongQuote();
        }

        // Make sure the underlying PT TWAP is working.
        _checkPtTwap(address(data.market), data.twapDuration);

        // Validate we support the pricing quote asset for this principal token.
        if (
            !IOracleRouter(centralRegistry.oracleRouter()).isSupportedAsset(
                data.quoteAsset
            )
        ) {
            revert PendlePrincipalTokenAdaptor__QuoteAssetIsNotSupported();
        }

        // Save adaptor data and update mapping that we support `asset` now.
        adaptorData[asset] = data;

        // Check whether this is new or updated support for `asset`.
        bool isUpdate;
        if (isSupportedAsset[asset]) {
            isUpdate = true;
        }

        isSupportedAsset[asset] = true;
        emit PendlePTAssetAdded(asset, data, isUpdate);
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
            revert PendlePrincipalTokenAdaptor__AssetIsNotSupported();
        }

        // Wipe config mapping entries for a gas refund.
        // Notify the adaptor to stop supporting the asset.
        delete isSupportedAsset[asset];
        delete adaptorData[asset];

        // Notify the Oracle Router that we are going to stop supporting
        // the asset.
        IOracleRouter(centralRegistry.oracleRouter()).notifyFeedRemoval(asset);
        emit PendlePTAssetRemoved(asset);
    }

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
            revert PendlePrincipalTokenAdaptor__CallIncreaseCardinality();
        }

        if (!oldestObservationSatisfied) {
            revert PendlePrincipalTokenAdaptor__OldestObservationIsNotSatisfied();
        }
    }
}
