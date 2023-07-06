// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import { ICurvePool } from "contracts/interfaces/external/curve/ICurvePool.sol";
import { Adaptor } from "contracts/oracles/adaptors/Adaptor.sol";
import { PriceOps } from "contracts/oracles/PriceOps.sol";
import { Math } from "contracts/libraries/Math.sol";
import { AutomationCompatibleInterface } from "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";
import { ERC20, SafeTransferLib } from "contracts/libraries/ERC4626.sol";
import { PendleLpOracleLib } from "@pendle/oracles/PendleLpOracleLib.sol";
import { IPMarket } from "@pendle/interfaces/IPMarket.sol";

interface IPendlePTOracle {
    function getOracleState(
        address market,
        uint32 duration
    )
        external
        view
        returns (
            bool increaseCardinalityRequired,
            uint16 cardinalityRequired,
            bool oldestObservationSatisfied
        );

    function getPtToAssetRate(
        address market,
        uint32 duration
    ) external view returns (uint256 ptToAssetRate);

    function getLpToAssetRate(
        address market,
        uint32 duration
    ) external view returns (uint256 ptToAssetRate);
}

interface IPendleMarket {
    function increaseObservationsCardinalityNext(
        uint16 cardinalityNext
    ) external;
}

contract PendleLPTokenAdaptor is Adaptor {
    using Math for uint256;
    using PendleLpOracleLib for IPMarket;

    uint32 public constant MINIMUM_TWAP_DURATION = 3600;
    IPendlePTOracle public immutable ptOracle;

    struct PendleLpAdaptorStorage {
        IPMarket market;
        address pt;
        uint32 twapDuration;
        address quoteAsset;
    }

    error PendleLPTokenAdaptor__MinimumTwapDurationNotMet();
    error PendleLPTokenAdaptor__OldestObservationNotSatisfied();
    error PendleLPTokenAdaptor__QuoteAssetNotSupported(
        address unsupportedQuote
    );
    error PendleLPTokenAdaptor__CallIncreaseObservationsCardinalityNext(
        address market,
        uint16 cardinalityNext
    );

    /**
     * @notice Curve Derivative Storage
     * @dev Stores an array of the underlying token addresses in the curve pool.
     */
    mapping(uint64 => PendleLpAdaptorStorage) public getPendleLpAdaptorStorage;

    constructor(
        PriceOps _priceOps,
        IPendlePTOracle _ptOracle
    ) Adaptor(_priceOps) {
        ptOracle = _ptOracle;
    }

    function setupSource(
        address asset,
        uint64 _sourceId,
        bytes memory data
    ) external override onlyPriceOps {
        PendleLpAdaptorStorage memory adaptorConfiguration = abi.decode(
            data,
            (PendleLpAdaptorStorage)
        );
        // TODO so now asset is the PMarket, and pt is the value that needs to be passed in struct
        // TODO check that market is the right one for the PT token.

        // TODO could probs move a lot of this code to a shared pendle contract.

        if (adaptorConfiguration.twapDuration < MINIMUM_TWAP_DURATION)
            revert PendleLPTokenAdaptor__MinimumTwapDurationNotMet();

        (
            bool increaseCardinalityRequired,
            uint16 cardinalityRequired,
            bool oldestObservationSatisfied
        ) = ptOracle.getOracleState(
                address(adaptorConfiguration.market),
                adaptorConfiguration.twapDuration
            );

        if (increaseCardinalityRequired)
            revert PendleLPTokenAdaptor__CallIncreaseObservationsCardinalityNext(
                asset,
                cardinalityRequired
            );

        if (oldestObservationSatisfied)
            revert PendleLPTokenAdaptor__OldestObservationNotSatisfied();

        // Check that `quoteAsset` is supported by PriceOps.
        if (!priceOps.isSupported(adaptorConfiguration.quoteAsset))
            revert PendleLPTokenAdaptor__QuoteAssetNotSupported(
                adaptorConfiguration.quoteAsset
            );

        // Write to adaptor storage.
        getPendleLpAdaptorStorage[_sourceId] = PendleLpAdaptorStorage({
            market: adaptorConfiguration.market,
            pt: asset,
            twapDuration: adaptorConfiguration.twapDuration,
            quoteAsset: adaptorConfiguration.quoteAsset
        });
    }

    function getPriceInBase(
        uint64 sourceId
    )
        external
        view
        override
        onlyPriceOps
        returns (uint256 upper, uint256 lower, uint8 errorCode)
    {
        PendleLpAdaptorStorage memory stor = getPendleLpAdaptorStorage[
            sourceId
        ];
        uint256 lpRate = stor.market.getLpToAssetRate(stor.twapDuration);
        (uint256 quoteUpper, uint256 quoteLower, uint8 _errorCode) = priceOps
            .getPriceInBase(stor.quoteAsset);
        if (errorCode == BAD_SOURCE || quoteUpper == 0) {
            // Completely blind as to what this price is return error code of BAD_SOURCE.
            return (0, 0, BAD_SOURCE);
        } else if (errorCode == CAUTION) errorCode = _errorCode;
        // Multiply the quote asset price by the lpRate to get the Lp Token fair value.
        quoteUpper = quoteUpper.mulDivDown(lpRate, 1e30);
        if (quoteLower > 0) quoteLower = quoteLower.mulDivDown(lpRate, 1e30);
        // TODO where does 1e30 come from?
    }
}
