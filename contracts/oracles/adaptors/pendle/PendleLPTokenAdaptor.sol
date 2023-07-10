// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { PriceRouter } from "contracts/oracles/PriceRouterV2.sol";
import "contracts/oracles/adaptors/BaseOracleAdaptor.sol";
import { PendleLpOracleLib } from "lib/pendle-core-v2-public/contracts/oracles/PendleLpOracleLib.sol";
import { IPendlePTOracle } from "contracts/interfaces/external/pendle/IPendlePtOracle.sol";
import { IPendleMarket } from "contracts/interfaces/external/pendle/IPendleMarket.sol";
import { IPMarket } from "lib/pendle-core-v2-public/contracts/interfaces/IPMarket.sol";

contract PendleLPTokenAdaptor is BaseOracleAdaptor {
    using PendleLpOracleLib for IPMarket;

    constructor(
        ICentralRegistry _centralRegistry,
        IPendlePTOracle _ptOracle,
        bool _pricesInUsd
    ) BaseOracleAdaptor(_centralRegistry, _pricesInUsd) {
        ptOracle = _ptOracle;
    }

    uint32 public constant MINIMUM_TWAP_DURATION = 3600;
    IPendlePTOracle public immutable ptOracle;

    struct AdaptorData {
        IPMarket market;
        uint32 twapDuration;
        address quoteAsset;
    }

    mapping(address => AdaptorData) public adaptorData;

    /// @param _asset the address of the Pendle market
    /// @param _data the adaptor data needed to add `_asset`
    function addAsset(
        address _asset,
        AdaptorData memory _data
    ) external override onlyDaoManager {
        // TODO check that market is the right one for the PT token.
        PriceRouter priceRouter = PriceRouter(centralRegistry.daoAddress());

        require(
            _data.twapDuration >= MINIMUM_TWAP_DURATION,
            "PendleLPTokenAdaptor: minimum twap duration not met"
        );

        (
            bool increaseCardinalityRequired,
            ,
            bool oldestObservationSatisfied
        ) = ptOracle.getOracleState(address(_data.market), _data.twapDuration);

        require(
            !increaseCardinalityRequired,
            "PendleLPTokenAdaptor: call increase observations cardinality"
        );
        require(
            oldestObservationSatisfied,
            "PendleLPTokenAdaptor: oldest observation not satisfied"
        );
        require(
            priceRouter.isSupportedAsset(_data.quoteAsset),
            "PendleLPTokenAdaptor: quote asset not supported"
        );

        // Write to adaptor storage.
        adaptorData[_asset] = AdaptorData({
            market: _data.market,
            twapDuration: _data.twapDuration,
            quoteAsset: _data.quoteAsset
        });
    }

    function getPrice(
        address _asset,
        bool _isUsd,
        bool _getLower
    ) external view override returns (PriceReturnData memory pData) {
        AdaptorData memory data = adaptorData[_asset];
        PriceRouter priceRouter = PriceRouter(centralRegistry.daoAddress());
        uint256 BAD_SOURCE = priceRouter.BAD_SOURCE();
        uint256 lpRate = data.market.getLpToAssetRate(data.twapDuration);
        pData.inUSD = _isUsd;
        (uint256 price, uint256 errorCode) = priceRouter.getPrice(
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

    /**
     * @notice Removes a supported asset from the adaptor.
     * @dev Calls back into price router to notify it of its removal
     */
    function removeAsset(address _asset) external override onlyDaoManager {
        require(
            isSupportedAsset[_asset],
            "PendleLPTokenAdaptor: asset not supported"
        );
        PriceRouter priceRouter = PriceRouter(centralRegistry.priceRouter());
        isSupportedAsset[_asset] = false;
        delete adaptorData[_asset];
        priceRouter.notifyAssetPriceFeedRemoval(_asset);
    }
}