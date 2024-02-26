pragma solidity 0.8.17;

import { WAD } from "contracts/libraries/Constants.sol";
import { IMToken } from "contracts/interfaces/market/IMToken.sol";
import { StatefulBaseMarket } from "tests/fuzzing/StatefulBaseMarket.sol";

contract FuzzLiquidations is StatefulBaseMarket {
    /// @notice the collateral token to be used in liquidations
    address collateralToken;
    /// @notice the debt token to be used in liquidations
    address debtToken;
    /// @notice the state of the entire system at the time of liquidation
    struct LiquidationData {
        bool isListed;
        uint256 collRatio;
        uint256 collReqSoft;
        uint256 collReqHard;
        uint256 liqBaseIncentive;
        uint256 liqCurve;
        uint256 liqFee;
        uint256 baseCFactor;
        uint256 cFactorCurve;
        uint256 lFactor;
        uint256 debtTokenPrice;
        uint256 collateralTokenPrice;
        uint256 debtBalanceCached;
        uint256 exchangeRateCached;
    }
    LiquidationData data;
    /// @notice how much the liquidator is intending to liquidate
    uint256 debtAmount;
    /// @notice stores intermediate calculated values as those that match the canLiquidate function
    struct IntermediateValues {
        uint256 cFactor;
        uint256 incentive;
        uint256 maxAmount;
        uint256 debtToCollateralRatio;
        uint256 amountAdjusted;
        uint256 liquidatedTokens;
        uint256 liquidatedTokenToProtocol;
    }
    IntermediateValues calculated;

    constructor() {
        collateralToken = address(cUSDC);
        debtToken = address(dDAI);
    }

    function calculateLiquidation_exact(uint256 amount) internal {
        // Setup state
        debtAmount = amount;
        _saveCurrentState();

        // Arithmetic calculation
        _calculateCFactor();
        _calculateIncentive();
        _calculateMaxAmount();
        _calculateDebtToCollateralRatio();
        _calculateAmountAdjusted();
        _calculateLiquidatedTokens();
        _calculateProtocolTokens();

        (
            uint256 _canLiq_debt,
            uint256 _canLiq_liquidatedTokens,
            uint256 _canLiqProtocol
        ) = marketManager.canLiquidate(
                debtToken,
                collateralToken,
                address(this),
                debtAmount,
                false
            );

        assertEq(
            debtAmount,
            _canLiq_debt,
            "LIQUIDATIONS - expected calculated debtAmount = can liquidate debt"
        );
        assertEq(
            calculated.liquidatedTokens,
            _canLiq_liquidatedTokens,
            "LIQUIDATED - expected liquidated tokens = can liquidate liquidate"
        );
        assertEq(
            calculated.liquidatedTokenToProtocol,
            _canLiqProtocol,
            "LIQUIDATED - expected liquidated tokens to protocol = can liquidate return value"
        );
    }

    /// @notice saves token data and liquidation status of system
    function _saveCurrentState() private {
        (
            bool isListed,
            uint256 collRatio,
            uint256 collReqSoft,
            uint256 collReqHard,
            uint256 liqBaseIncentive,
            uint256 liqCurve,
            uint256 liqFee,
            uint256 baseCFactor,
            uint256 cfactorCurve
        ) = marketManager.tokenData(debtToken);
        (
            uint256 lFactor,
            uint256 debtTokenPrice,
            uint256 collateralTokenPrice
        ) = marketManager.LiquidationStatusOf(
                address(this),
                debtToken,
                collateralToken
            );
        uint256 debtBalanceCached = IMToken(debtToken).debtBalanceCached(
            address(this)
        );
        uint256 exchangeRateCached = IMToken(debtToken).exchangeRateCached();

        data = LiquidationData(
            isListed,
            collRatio,
            collReqSoft,
            collReqHard,
            liqBaseIncentive,
            liqCurve,
            liqFee,
            baseCFactor,
            cfactorCurve,
            lFactor,
            debtTokenPrice,
            collateralTokenPrice,
            debtBalanceCached,
            exchangeRateCached
        );
    }

    /// @custom:property liq-1 The baseCFactor must be bound between  MIN_BASE_CFACTOR and MAX_BASE_CFACTOR
    /// @custom:property liq-2 The lFactor must be bound between 1 and WAD.
    /// @custom:property liq-3 cFactor from calculation must be between WAD and MAX_BASE_CFACTOR
    /// @custom:precondition baseCFactor > MIN_BASE_CFACTOR
    /// @custom:precondition baseCFactor <= MAX_BASE_CFACTOR
    /// @custom:precondition lFactor > 0
    /// @custom:precondition l factor <= WAD
    function _calculateCFactor() private {
        // Preconditions
        assertWithMsg(
            data.baseCFactor >= marketManager.MIN_BASE_CFACTOR(),
            "LIQ-1 - c base c factor must be >= to MIN_BASE_CFACTOR"
        );
        assertWithMsg(
            data.baseCFactor <= marketManager.MAX_BASE_CFACTOR(),
            "LIQ-1 - data.baseCFactor must be <= MAX_BASE_CFACTOR"
        );
        assertWithMsg(data.lFactor > 0, "L factor must be > 0 ");
        assertWithMsg(data.lFactor <= WAD, "LIQ-2 - L factor must be <= WAD");

        uint256 cFactor = data.baseCFactor +
            (data.cFactorCurve * data.lFactor) /
            WAD;

        // Postconditions
        assertWithMsg(
            cFactor >= data.baseCFactor && cFactor <= WAD,
            "LIQ-3 - c factor result must be bound between [data.baseCFactor, WAD]"
        );
        calculated.cFactor = cFactor;
    }

    /// @custom:property liq-4 incentive must be <= MAX_LIQUIDATION_INCENTIVE
    /// @custom:property liq-4 incentive must be >= MIN_LIQUIDATION_INCENTIVE
    /// @custom:property liq-5 resullting incentive must be bound between MIN_LIQUIDATION_INCENTIVE to MAX_LIQUIDATION_INCENTIVE
    /// @custom:precondition liqBaseIncentive must be <= MAX_LIQUIDATION_INCENTIVE
    /// @custom:precondition incentive must be >= MIN_LIQUIDATION_INCENTIVE
    function _calculateIncentive() private {
        // Preconditions
        assertWithMsg(
            data.liqBaseIncentive >= marketManager.MIN_LIQUIDATION_INCENTIVE(),
            "LIQ-4 - data.liqBaseIncentive must be >= MIN_LIQUIDATION_INCENTIVE"
        );
        assertWithMsg(
            data.liqBaseIncentive <= marketManager.MAX_LIQUIDATION_INCENTIVE(),
            "LIQ-4 - data.liqBaseIncentive must be <= MAX_LIQUIDATION_INCENTIVE"
        );

        uint256 incentive = data.liqBaseIncentive +
            (data.liqCurve * data.lFactor) /
            WAD;

        // Postconditions
        assertWithMsg(
            incentive >= marketManager.MIN_LIQUIDATION_INCENTIVE(),
            "LIQ-5 - incentive must be >= MIN_LIQUIDATION_INCENTIVE"
        );
        assertWithMsg(
            incentive <= marketManager.MAX_LIQUIDATION_INCENTIVE(),
            "LIQ-5 - incentive must be <= MAX_LIQUIDATION_INCENTIVE"
        );
        calculated.incentive = incentive;
    }

    /// @custom:property liq-6 if cfactor == 0, maxAmount to be liquidated = 0
    /// @custom:property liq-7 if cFactor == WAD, maxAmount to be liquidated = debtBalanceCached
    /// @custom:property liq-8 if cFactor is between [0, WAD], maxAmount to be liquidated must be bound between [0, debtBalanceCached]
    function _calculateMaxAmount() private {
        // Preconditions

        uint256 maxAmount = (calculated.cFactor * data.debtBalanceCached) /
            WAD;

        // Postconditions
        if (calculated.cFactor == 0) {
            assertWithMsg(
                maxAmount == 0,
                "LIQ-6 - maxAmount = 0 when calculated.cFactor = 0"
            );
        } else if (calculated.cFactor == WAD) {
            assertWithMsg(
                maxAmount == data.debtBalanceCached,
                "LIQ-7 - maxAmount = data.debtBalanceCached when calculated.cFactor = WAD"
            );
        } else {
            assertGt(maxAmount, 0, "LIQUIDATIONS - maxAmount must be >0");
            assertLt(
                maxAmount,
                data.debtBalanceCached,
                "LIQ-8 - maxAmount must be <= data.debtBalanceCached"
            );
        }
        calculated.maxAmount = maxAmount;
    }

    /// @custom:notice No property bounds as debt to collateral ratio can be unbounded
    function _calculateDebtToCollateralRatio() private {
        // No Preconditions

        uint256 debtToCollateralRatio = (calculated.incentive *
            data.debtTokenPrice *
            WAD) / (data.collateralTokenPrice * data.exchangeRateCached);

        // No Postconditions
        calculated.debtToCollateralRatio = debtToCollateralRatio;
    }

    /// @custom:property liq-9 if collateral token and debt token have the same number of decimals, amountAdjusted = debtBalanceCached
    /// @custom:property liq-10 if collateral token decimals > debtTokenDecimals, amountAdjusted > debtBalanceCached
    /// @custom:property liq-11 if collateral token decimals < debtTokenDecimals, amountAdjusted < debtBalanceCached
    function _calculateAmountAdjusted() private {
        // Saves state
        uint256 collateralTokenDecimals = IMToken(collateralToken).decimals();
        uint256 debtTokenDecimals = IMToken(debtToken).decimals();

        uint256 amountAdjusted = (data.debtBalanceCached *
            10 ** collateralTokenDecimals) / (10 ** debtTokenDecimals);

        // Postconditions
        if (collateralTokenDecimals == debtTokenDecimals) {
            assertEq(
                amountAdjusted,
                data.debtBalanceCached,
                "LIQ-9 - when collat token dec == debt token dec, amountAdjusted = debtAmount"
            );
        } else if (collateralTokenDecimals > debtTokenDecimals) {
            assertGt(
                amountAdjusted,
                data.debtBalanceCached,
                "LIQ-10 - amountAdjusted > debtBalanceCached when collateral token < debt token decimals"
            );
        } else if (collateralTokenDecimals < debtTokenDecimals) {
            assertLt(
                amountAdjusted,
                data.debtBalanceCached,
                "LIQ-11 - amountAdjusted < debtBalanceCached when collateral token < debt token decimals"
            );
        }
        calculated.amountAdjusted = amountAdjusted;
    }

    /// @custom:property liq-12 if amountAdjusted == 0, tokens to be liquidated = 0
    /// @custom:property liq-13 if debtToCollateralRatio == 0, tokens to be liquidated = 0
    function _calculateLiquidatedTokens() private {
        uint256 liquidatedTokens = (calculated.amountAdjusted *
            calculated.debtToCollateralRatio) / WAD;

        // Postconditions
        if (calculated.amountAdjusted == 0) {
            assertEq(
                liquidatedTokens,
                0,
                "LIQ-12 - liquidatedTokens = 0 when amountAdjusted = 0 "
            );
        } else if (calculated.debtToCollateralRatio == 0) {
            assertEq(
                liquidatedTokens,
                0,
                "LIQ-13 - liquidatedTokens = 0 when amountAdjusted = 0 "
            );
        }
        calculated.liquidatedTokens = liquidatedTokens;
    }

    // No pre or post conditions relevant here
    function _calculateProtocolTokens() private {
        calculated.liquidatedTokenToProtocol =
            (calculated.liquidatedTokens * data.liqFee) /
            WAD;
    }
}
