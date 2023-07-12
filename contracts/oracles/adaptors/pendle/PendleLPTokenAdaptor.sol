// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import { BaseOracleAdaptor } from "contracts/oracles/adaptors/BaseOracleAdaptor.sol";
import { IPriceRouter } from "contracts/interfaces/IPriceRouter.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { PendleLpOracleLib } from "contracts/libraries/pendle/PendleLpOracleLib.sol";
import { IPendlePTOracle } from "contracts/interfaces/external/pendle/IPendlePtOracle.sol";
import { IPMarket, IPPrincipalToken, IStandardizedYield } from "contracts/interfaces/external/pendle/IPMarket.sol";
import { IOracleAdaptor, PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";

contract PendleLPTokenAdaptor is BaseOracleAdaptor {
    using PendleLpOracleLib for IPMarket;

    /// @notice Adaptor storage
    /// @param twapDuration the twap duration to use when pricing
    /// @param quoteAsset the asset the twap quote is provided in
    /// @param pt the address of the Pendle PT associated with LP.
    struct AdaptorData {
        uint32 twapDuration;
        address quoteAsset;
        address pt;
    }

    /// @notice Pendle LP adaptor storage
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
    /// @param _asset the pendle market token being priced
    /// @param _isUsd indicates whether we want the price in USD or ETH
    /// @param _getLower Since this adaptor calls back into the price router
    ///                  it needs to know if it should be working with the upper
    ///                  or lower prices of assets
    function getPrice(
        address _asset,
        bool _isUsd,
        bool _getLower
    ) external view override returns (PriceReturnData memory pData) {
        AdaptorData memory data = adaptorData[_asset];
        uint256 lpRate = IPMarket(_asset).getLpToAssetRate(data.twapDuration);
        pData.inUSD = _isUsd;
        
        (uint256 price, uint256 errorCode) = IPriceRouter(centralRegistry.priceRouter()).getPrice(
            data.quoteAsset,
            _isUsd,
            _getLower
        );
        if (errorCode > 0) {
            pData.hadError = true;
            // If error code is BAD_SOURCE we can't use this price at all so return.
            if (errorCode == BAD_SOURCE) return pData;
        }

        // Multiply the quote asset price by the lpRate to get the Lp Token fair value.
        pData.price = uint240((price * lpRate) / 1e30);
        // TODO where does 1e30 come from?
    }

    /// @notice Add a Pendle Market as an asset.
    /// @dev Should be called before `PriceRotuer:addAssetPriceFeed` is called.
    /// @param _asset the address of the Pendle Market
    /// @param _data the adaptor data needed to add `_asset`
    function addAsset(
        address _asset,
        AdaptorData memory _data
    ) external onlyDaoManager {
        // Make sure pt and market match.
        (IStandardizedYield sy, IPPrincipalToken pt, ) = IPMarket(_asset)
            .readTokens();
        require(address(pt) == _data.pt, "PendleLPTokenAdaptor: wrong market");
        // Make sure quote asset is the same as SY `assetInfo.assetAddress`
        (, address assetAddress, ) = sy.assetInfo();
        require(
            assetAddress == _data.quoteAsset,
            "PendleLPTokenAdaptor: wrong quote"
        );

        require(
            _data.twapDuration >= MINIMUM_TWAP_DURATION,
            "PendleLPTokenAdaptor: minimum twap duration not met"
        );

        // Make sure the underlying PT TWAP is working.
        (
            bool increaseCardinalityRequired,
            ,
            bool oldestObservationSatisfied
        ) = ptOracle.getOracleState(address(_data.pt), _data.twapDuration);

        require(
            !increaseCardinalityRequired,
            "PendleLPTokenAdaptor: call increase observations cardinality"
        );
        require(
            oldestObservationSatisfied,
            "PendleLPTokenAdaptor: oldest observation not satisfied"
        );
        require(
            IPriceRouter(centralRegistry.priceRouter()).isSupportedAsset(_data.quoteAsset),
            "PendleLPTokenAdaptor: quote asset not supported"
        );

        // Write to adaptor storage.
        adaptorData[_asset] = AdaptorData({
            twapDuration: _data.twapDuration,
            quoteAsset: _data.quoteAsset,
            pt: _data.pt
        });
    }

    /// @notice Removes a supported asset from the adaptor.
    /// @dev Calls back into price router to notify it of its removal
    function removeAsset(address _asset) external override onlyDaoManager {
        require(
            isSupportedAsset[_asset],
            "PendleLPTokenAdaptor: asset not supported"
        );
        /// Notify the adaptor to stop supporting the asset 
        delete isSupportedAsset[_asset];

        /// Wipe config mapping entries for a gas refund
        delete adaptorData[_asset];

        /// Notify the price router that we are going to stop supporting the asset 
        IPriceRouter(centralRegistry.priceRouter()).notifyAssetPriceFeedRemoval(_asset);
    }
}
