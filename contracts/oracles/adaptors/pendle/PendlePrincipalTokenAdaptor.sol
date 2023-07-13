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
    /// @param _asset the pendle principal token being priced
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
        pData.inUSD = _isUsd;
        uint256 ptRate = data.market.getPtToAssetRate(data.twapDuration);

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
        // Multiply the quote asset price by the ptRate to get the Principal Token fair value.
        pData.price = uint240((price * ptRate) / 1e30);
        // TODO where does 1e30 come from?
    }

    /// @notice Add a Pendle Principal Token as an asset.
    /// @dev Should be called before `PriceRotuer:addAssetPriceFeed` is called.
    /// @param _asset the address of the Pendle PT
    /// @param _data the adaptor data needed to add `_asset`
    function addAsset(
        address _asset,
        AdaptorData memory _data
    ) external onlyDaoManager {
        // Make sure pt and market match.
        (IStandardizedYield sy, IPPrincipalToken pt, ) = _data
            .market
            .readTokens();
        require(
            address(pt) == _asset,
            "PendlePrincipalTokenAdaptor: wrong market"
        );
        // Make sure quote asset is the same as SY `assetInfo.assetAddress`
        (, address assetAddress, ) = sy.assetInfo();
        require(
            assetAddress == _data.quoteAsset,
            "PendlePrincipalTokenAdaptor: wrong quote"
        );

        require(
            _data.twapDuration >= MINIMUM_TWAP_DURATION,
            "PendlePrincipalTokenAdaptor: minimum twap duration not met"
        );

        (
            bool increaseCardinalityRequired,
            ,
            bool oldestObservationSatisfied
        ) = ptOracle.getOracleState(address(_data.market), _data.twapDuration);

        require(
            !increaseCardinalityRequired,
            "PendlePrincipalTokenAdaptor: call increase observations cardinality"
        );
        require(
            oldestObservationSatisfied,
            "PendlePrincipalTokenAdaptor: oldest observation not satisfied"
        );
        require(
            IPriceRouter(centralRegistry.priceRouter()).isSupportedAsset(_data.quoteAsset),
            "PendlePrincipalTokenAdaptor: quote asset not supported"
        );

        // Write to extension storage.
        adaptorData[_asset] = AdaptorData({
            market: _data.market,
            twapDuration: _data.twapDuration,
            quoteAsset: _data.quoteAsset
        });
    }

    /// @notice Removes a supported asset from the adaptor.
    /// @dev Calls back into price router to notify it of its removal
    function removeAsset(address _asset) external override onlyDaoManager {
        require(
            isSupportedAsset[_asset],
            "PendlePrincipalTokenAdaptor: asset not supported"
        );
        
        /// Notify the adaptor to stop supporting the asset 
        delete isSupportedAsset[_asset];

        /// Wipe config mapping entries for a gas refund
        delete adaptorData[_asset];

        /// Notify the price router that we are going to stop supporting the asset 
        IPriceRouter(centralRegistry.priceRouter()).notifyAssetPriceFeedRemoval(_asset);
    }
}
