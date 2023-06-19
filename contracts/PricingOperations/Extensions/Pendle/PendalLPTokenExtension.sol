// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import { ICurvePool } from "contracts/interfaces/Curve/ICurvePool.sol";
import { Extension } from "contracts/PricingOperations/Extension.sol";
import { PriceOps } from "contracts/PricingOperations/PriceOps.sol";
import { Math } from "contracts/utils/Math.sol";
import { AutomationCompatibleInterface } from "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";
import { ERC20, SafeTransferLib } from "contracts/base/ERC4626.sol";
import { PendleLpOracleLib } from "@pendle/oracles/PendleLpOracleLib.sol";
import { IPMarket } from "@pendle/interfaces/IPMarket.sol";

interface IPendlePTOracle {
    function getOracleState(
        address market,
        uint32 duration
    )
        external
        view
        returns (bool increaseCardinalityRequired, uint16 cardinalityRequired, bool oldestObservationSatisfied);

    function getPtToAssetRate(address market, uint32 duration) external view returns (uint256 ptToAssetRate);

    function getLpToAssetRate(address market, uint32 duration) external view returns (uint256 ptToAssetRate);
}

interface IPendleMarket {
    function increaseObservationsCardinalityNext(uint16 cardinalityNext) external;
}

contract PendalLPTokenExtension is Extension {
    using Math for uint256;
    using PendleLpOracleLib for IPMarket;

    uint32 public constant MINIMUM_TWAP_DURATION = 3600;
    IPendlePTOracle public immutable ptOracle;

    struct PendalLpExtensionStorage {
        IPMarket market;
        address pt;
        uint32 twapDuration;
        address quoteAsset;
    }

    error PendalLPTokenExtension__MinimumTwapDurationNotMet();
    error PendalLPTokenExtension__OldestObservationNotSatisfied();
    error PendalLPTokenExtension__QuoteAssetNotSupported(address unsupportedQuote);
    error PendalLPTokenExtension__CallIncreaseObservationsCardinalityNext(address market, uint16 cardinalityNext);

    /**
     * @notice Curve Derivative Storage
     * @dev Stores an array of the underlying token addresses in the curve pool.
     */
    mapping(uint64 => PendalLpExtensionStorage) public getPendalLpExtensionStorage;

    constructor(PriceOps _priceOps, IPendlePTOracle _ptOracle) Extension(_priceOps) {
        ptOracle = _ptOracle;
    }

    function setupSource(address asset, uint64 _sourceId, bytes memory data) external override onlyPriceOps {
        PendalLpExtensionStorage memory extensionConfiguration = abi.decode(data, (PendalLpExtensionStorage));
        // TODO so now asset is the PMarket, and pt is the value that needs to be passed in struct
        // TODO check that market is the right one for the PT token.

        // TODO could probs move a lot of this code to a shared pendle contract.

        if (extensionConfiguration.twapDuration < MINIMUM_TWAP_DURATION)
            revert PendalLPTokenExtension__MinimumTwapDurationNotMet();

        (bool increaseCardinalityRequired, uint16 cardinalityRequired, bool oldestObservationSatisfied) = ptOracle
            .getOracleState(address(extensionConfiguration.market), extensionConfiguration.twapDuration);

        if (increaseCardinalityRequired)
            revert PendalLPTokenExtension__CallIncreaseObservationsCardinalityNext(asset, cardinalityRequired);

        if (oldestObservationSatisfied) revert PendalLPTokenExtension__OldestObservationNotSatisfied();

        // Check that `quoteAsset` is supported by PriceOps.
        if (!priceOps.isSupported(extensionConfiguration.quoteAsset))
            revert PendalLPTokenExtension__QuoteAssetNotSupported(extensionConfiguration.quoteAsset);

        // Write to extension storage.
        getPendalLpExtensionStorage[_sourceId] = PendalLpExtensionStorage({
            market: extensionConfiguration.market,
            pt: asset,
            twapDuration: extensionConfiguration.twapDuration,
            quoteAsset: extensionConfiguration.quoteAsset
        });
    }

    function getPriceInBase(
        uint64 sourceId
    ) external view override onlyPriceOps returns (uint256 upper, uint256 lower, uint8 errorCode) {
        PendalLpExtensionStorage memory stor = getPendalLpExtensionStorage[sourceId];
        uint256 lpRate = stor.market.getLpToAssetRate(stor.twapDuration);
        (uint256 quoteUpper, uint256 quoteLower, uint8 _errorCode) = priceOps.getPriceInBase(stor.quoteAsset);
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
