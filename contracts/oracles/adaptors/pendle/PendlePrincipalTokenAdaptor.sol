// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import { ICurvePool } from "contracts/interfaces/external/curve/ICurvePool.sol";
import { Extension } from "contracts/oracles/adaptors/Extension.sol";
import { PriceOps } from "contracts/oracles/PriceOps.sol";
import { Math } from "contracts/libraries/Math.sol";
import { ERC20, SafeTransferLib } from "contracts/libraries/ERC4626.sol";

import { IPPtOracle } from "@pendle/interfaces/IPPtOracle.sol";
import { PendlePtOracleLib } from "@pendle/oracles/PendlePtOracleLib.sol";
import { IPMarket } from "@pendle/interfaces/IPMarket.sol";

contract PendlePrincipalTokenExtension is BaseOracleAdaptor {
    using Math for uint256;
    using PendlePtOracleLib for IPMarket;

    uint32 public constant MINIMUM_TWAP_DURATION = 3600;
    IPPtOracle public immutable ptOracle;

    struct PendlePrincipalExtensionStorage {
        address market;
        address pt;
        uint32 twapDuration;
        address quoteAsset;
    }

    error PendlePrincipalTokenExtension__MinimumTwapDurationNotMet();
    error PendlePrincipalTokenExtension__OldestObservationNotSatisfied();
    error PendlePrincipalTokenExtension__QuoteAssetNotSupported(
        address unsupportedQuote
    );
    error PendlePrincipalTokenExtension__CallIncreaseObservationsCardinalityNext(
        address market,
        uint16 cardinalityNext
    );

    /**
     * @notice Curve Derivative Storage
     * @dev Stores an array of the underlying token addresses in the curve pool.
     */
    mapping(uint64 => PendlePrincipalExtensionStorage)
        public getPendlePrincipalExtensionStorage;

    constructor(
        PriceOps _priceOps,
        IPPtOracle _ptOracle
    ) Extension(_priceOps) {
        ptOracle = _ptOracle;
    }

    function setupSource(
        address asset,
        uint64 _sourceId,
        bytes calldata data
    ) external override onlyPriceOps {
        PendlePrincipalExtensionStorage memory extensionConfiguration = abi
            .decode(data, (PendlePrincipalExtensionStorage));

        // TODO check that market is the right one for the PT token.

        if (extensionConfiguration.twapDuration < MINIMUM_TWAP_DURATION)
            revert PendlePrincipalTokenExtension__MinimumTwapDurationNotMet();

        (
            bool increaseCardinalityRequired,
            uint16 cardinalityRequired,
            bool oldestObservationSatisfied
        ) = ptOracle.getOracleState(
                extensionConfiguration.market,
                extensionConfiguration.twapDuration
            );

        if (increaseCardinalityRequired)
            revert PendlePrincipalTokenExtension__CallIncreaseObservationsCardinalityNext(
                asset,
                cardinalityRequired
            );

        if (oldestObservationSatisfied)
            revert PendlePrincipalTokenExtension__OldestObservationNotSatisfied();

        // Check that `quoteAsset` is supported by PriceOps.
        if (!priceOps.isSupported(extensionConfiguration.quoteAsset))
            revert PendlePrincipalTokenExtension__QuoteAssetNotSupported(
                extensionConfiguration.quoteAsset
            );

        // Write to extension storage.
        getPendlePrincipalExtensionStorage[
            _sourceId
        ] = PendlePrincipalExtensionStorage({
            market: extensionConfiguration.market,
            pt: asset,
            twapDuration: extensionConfiguration.twapDuration,
            quoteAsset: extensionConfiguration.quoteAsset
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
        PendlePrincipalExtensionStorage
            memory stor = getPendlePrincipalExtensionStorage[sourceId];
        uint256 ptRate = ptOracle.getPtToAssetRate(stor.pt, stor.twapDuration);
        (uint256 quoteUpper, uint256 quoteLower, uint8 _errorCode) = priceOps
            .getPriceInBase(stor.quoteAsset);
        if (errorCode == BAD_SOURCE || quoteUpper == 0) {
            // Completely blind as to what this price is return error code of BAD_SOURCE.
            return (0, 0, BAD_SOURCE);
        } else if (errorCode == CAUTION) errorCode = _errorCode;
        // Multiply the quote asset price by the ptRate to get the Principal Token fair value.
        quoteUpper = quoteUpper.mulDivDown(ptRate, 1e30);
        if (quoteLower > 0) quoteLower = quoteLower.mulDivDown(ptRate, 1e30);
        // TODO where does 1e30 come from?
    }
}
