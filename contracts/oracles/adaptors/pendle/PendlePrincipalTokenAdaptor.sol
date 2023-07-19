// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import { BaseOracleAdaptor } from "contracts/oracles/adaptors/BaseOracleAdaptor.sol";
import { IPriceRouter } from "contracts/interfaces/IPriceRouter.sol";
import { PendlePtOracleLib } from "contracts/libraries/pendle/PendlePtOracleLib.sol";
import { IPMarket, IPPrincipalToken, IStandardizedYield } from "contracts/interfaces/external/pendle/IPMarket.sol";
import { IPendlePTOracle } from "contracts/interfaces/external/pendle/IPendlePtOracle.sol";
import { IOracleAdaptor, PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract PendlePrincipalTokenAdaptor is BaseOracleAdaptor {
    using PendlePtOracleLib for IPMarket;

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

    /// @notice Pendle PT adaptor storage
    mapping(address => AdaptorData) public adaptorData;

    /// @notice The minimum acceptable twap duration when pricing
    uint32 public constant MINIMUM_TWAP_DURATION = 3600;

    /// @notice Current networks ptOracle
    /// @dev for mainnet use 0x414d3C8A26157085f286abE3BC6E1bb010733602
    IPendlePTOracle public immutable ptOracle;

    /// @notice Error code for bad source.
    uint256 public constant BAD_SOURCE = 2;

    constructor(
        ICentralRegistry _centralRegistry,
        IPendlePTOracle _ptOracle
    ) BaseOracleAdaptor(_centralRegistry) {
        ptOracle = _ptOracle;
    }

    /// @notice Called during pricing operations.
    /// @param asset the pendle principal token being priced
    /// @param isUsd indicates whether we want the price in USD or ETH
    /// @param getLower Since this adaptor calls back into the price router
    ///                  it needs to know if it should be working with the upper
    ///                  or lower prices of assets
    function getPrice(
        address asset,
        bool isUsd,
        bool getLower
    ) external view override returns (PriceReturnData memory pData) {
        require(
            isSupportedAsset[asset],
            "PendlePrincipalTokenAdaptor: asset not supported"
        );
        AdaptorData memory data = adaptorData[asset];
        pData.inUSD = isUsd;
        uint256 ptRate = data.market.getPtToAssetRate(data.twapDuration);

        (uint256 price, uint256 errorCode) = IPriceRouter(
            centralRegistry.priceRouter()
        ).getPrice(data.quoteAsset, isUsd, getLower);
        if (errorCode > 0) {
            pData.hadError = true;
            // If error code is BAD_SOURCE we can't use this price at all so return.
            if (errorCode == BAD_SOURCE) return pData;
        }
        // Multiply the quote asset price by the ptRate to get the Principal Token fair value.
        pData.price = uint240(
            (price * ptRate) / 10 ** data.quoteAssetDecimals
        );
    }

    /// @notice Add a Pendle Principal Token as an asset.
    /// @dev Should be called before `PriceRotuer:addAssetPriceFeed` is called.
    /// @param asset the address of the Pendle PT
    /// @param data the adaptor data needed to add `asset`
    function addAsset(
        address asset,
        AdaptorData memory data
    ) external onlyElevatedPermissions {
        // Make sure pt and market match.
        (IStandardizedYield sy, IPPrincipalToken pt, ) = data
            .market
            .readTokens();
        require(
            address(pt) == asset,
            "PendlePrincipalTokenAdaptor: wrong market"
        );
        // Make sure quote asset is the same as SY `assetInfo.assetAddress`
        (, address assetAddress, ) = sy.assetInfo();
        require(
            assetAddress == data.quoteAsset,
            "PendlePrincipalTokenAdaptor: wrong quote"
        );

        require(
            data.twapDuration >= MINIMUM_TWAP_DURATION,
            "PendlePrincipalTokenAdaptor: minimum twap duration not met"
        );

        (
            bool increaseCardinalityRequired,
            ,
            bool oldestObservationSatisfied
        ) = ptOracle.getOracleState(address(data.market), data.twapDuration);

        require(
            !increaseCardinalityRequired,
            "PendlePrincipalTokenAdaptor: call increase observations cardinality"
        );
        require(
            oldestObservationSatisfied,
            "PendlePrincipalTokenAdaptor: oldest observation not satisfied"
        );
        require(
            IPriceRouter(centralRegistry.priceRouter()).isSupportedAsset(
                data.quoteAsset
            ),
            "PendlePrincipalTokenAdaptor: quote asset not supported"
        );

        // Write to extension storage.
        adaptorData[asset] = AdaptorData({
            market: data.market,
            twapDuration: data.twapDuration,
            quoteAsset: data.quoteAsset,
            quoteAssetDecimals: data.quoteAssetDecimals
        });
    }

    /// @notice Removes a supported asset from the adaptor.
    /// @dev Calls back into price router to notify it of its removal
    /// @param asset The address of the asset to be removed.
    function removeAsset(address asset) external override onlyDaoPermissions {
        require(
            isSupportedAsset[asset],
            "PendlePrincipalTokenAdaptor: asset not supported"
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
