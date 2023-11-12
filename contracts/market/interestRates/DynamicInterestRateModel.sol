// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { WAD } from "contracts/libraries/Constants.sol";

contract DynamicInterestRateModel {

    struct DynamicRatesData {
        /// VERTEX CONFIGURATION ///
        // @notice The timestamp when the vertex multiplier will next be updated
        uint128 nextUpdateTimestamp;
        // @notice The current rate at which vertexInterestRate is multiplied, in WAD
        uint128 vertexMultiplier;
    }

    struct RatesConfiguration {
        // @notice Base rate at which interest is accumulated, per compound
        uint256 baseInterestRate;
        // @notice Vertex rate at which interest is accumulated, per compound
        uint256 vertexInterestRate;
        // @notice Utilization rate point where vertex rate is used instead of base rate
        uint256 vertexStartingPoint;
        // @notice The rate at which the vertex multiplier is adjusted, in seconds
        uint256 adjustmentRate;
        // @notice The maximum rate at with the vertex multiplier is adjusted, in WAD
        uint256 adjustmentVelocity;
        // @notice Rate at which the vertex multiplier will decay per update, in WAD
        uint256 decayRate;
        // @notice The utilization rate at which the vertex multiplier will begin to increase
        uint256 increaseThreshold;
        // @notice The utilization rate at which the vertex multiplier positive velocity will max out
        uint256 increaseThresholdMax;
        // @notice The utilization rate at which the vertex multiplier will begin to decrease
        uint256 decreaseThreshold;
        // @notice The utilization rate at which the vertex multiplier negative velocity will max out
        uint256 decreaseThresholdMax;
    }

    /// CONSTANTS ///

    /// Unix time has 31,536,000 seconds per year
    /// All my homies hate leap seconds and leap years
    uint256 internal constant SECONDS_PER_YEAR = 31536000;
    /// @notice Rate at which interest is compounded, in seconds
    uint256 internal constant INTEREST_COMPOUND_RATE = 600;
    // @notice Maximum Rate at which the vertex multiplier will decay per update, in WAD
    uint256 internal constant MAX_VERTEX_DECAY_RATE = .05e18; // 5%
    /// @notice The minimum frequency in which the vertex can have between adjustments
    uint256 internal constant MIN_VERTEX_ADJUSTMENT_RATE = 4 hours;
    /// @notice The maximum frequency in which the vertex can have between adjustments
    uint256 internal constant MAX_VERTEX_ADJUSTMENT_RATE = 3 days;
    // @notice The maximum rate at with the vertex multiplier is adjusted, in WAD on top of base rate (1 WAD)
    uint256 internal constant MAX_VERTEX_ADJUSTMENT_VELOCITY = 3 * WAD; // triples per adjustment rate
    /// @notice For external contract's to call for validation
    bool public constant IS_INTEREST_RATE_MODEL = true;
    /// @notice Curvance DAO hub
    ICentralRegistry public immutable centralRegistry;

    /// STORAGE ///

    DynamicRatesData public currentRates;
    RatesConfiguration public ratesConfig;

    /// EVENTS ///

    event NewDynamicInterestRateModel(
        uint256 baseInterestRate,
        uint256 vertexInterestRate,
        uint256 vertexStartingPoint,
        uint256 adjustmentRate,
        uint256 adjustmentVelocity,
        uint256 decayRate,
        uint256 increaseThreshold,
        uint256 increaseThresholdMax,
        uint256 decreaseThreshold,
        uint256 decreaseThresholdMax,
        bool vertexReset
    );

    /// ERRORS ///

    error DynamicInterestRateModel__Unauthorized();
    error DynamicInterestRateModel__InvalidCentralRegistry();
    error DynamicInterestRateModel__InvalidAdjustmentRate();
    error DynamicInterestRateModel__InvalidAdjustmentVelocity();
    error DynamicInterestRateModel__InvalidDecayRate();
    

    /// MODIFIERS ///

    modifier onlyElevatedPermissions() {
        if (!centralRegistry.hasElevatedPermissions(msg.sender)) {
            revert DynamicInterestRateModel__Unauthorized();
        }
        _;
    }

    /// CONSTRUCTOR ///

    /// @notice Construct an interest rate model
    /// @param baseRatePerYear The rate of increase in interest rate by
    ///                        utilization rate (in basis points)
    /// @param vertexRatePerYear The multiplierPerSecond after hitting
    ///                          `vertexUtilizationStart` utilization rate
    /// @param vertexUtilizationStart The utilization point at which the vertex rate
    ///                               is applied
    /// @param adjustmentRate The rate at which the vertex multiplier is adjusted, 
    ///                             in seconds
    /// @param adjustmentVelocity The maximum rate at with the vertex multiplier is adjusted, 
    ///                                 in basis points
    constructor(
        ICentralRegistry centralRegistry_,
        uint256 baseRatePerYear,
        uint256 vertexRatePerYear,
        uint256 vertexUtilizationStart,
        uint256 adjustmentRate,
        uint256 adjustmentVelocity,
        uint256 decayRate
    ) {

        if (
            !ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            )
        ) {
            revert DynamicInterestRateModel__InvalidCentralRegistry();
        }

        centralRegistry = centralRegistry_;

        _updateDynamicInterestRateModel(
            baseRatePerYear,
            vertexRatePerYear,
            vertexUtilizationStart,
            adjustmentRate,
            adjustmentVelocity,
            decayRate,
            true
        );
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Update the parameters of the interest rate model
    ///         (only callable by Curvance DAO elevated permissions, i.e. Timelock)
    /// @param baseRatePerYear The rate of increase in interest rate by
    ///                          utilization rate (scaled by WAD)
    /// @param vertexRatePerYear The multiplierPerSecond after hitting
    ///                              `vertex` utilization rate
    /// @param vertexUtilizationStart The utilization point at which the jump multiplier
    ///                               is applied
    function updateDynamicInterestRateModel(
        uint256 baseRatePerYear,
        uint256 vertexRatePerYear,
        uint256 vertexUtilizationStart,
        uint256 adjustmentRate,
        uint256 adjustmentVelocity,
        uint256 decayRate,
        bool vertexReset
    ) external onlyElevatedPermissions {
        _updateDynamicInterestRateModel(
            baseRatePerYear,
            vertexRatePerYear,
            vertexUtilizationStart,
            adjustmentRate,
            adjustmentVelocity,
            decayRate,
            vertexReset
        );
    }

    /// PUBLIC FUNCTIONS ///

    /// @notice Calculates the utilization rate of the market:
    ///         `borrows / (cash + borrows - reserves)`
    /// @param cash The amount of cash in the market
    /// @param borrows The amount of borrows in the market
    /// @param reserves The amount of reserves in the market
    /// @return The utilization rate between [0, WAD]
    function utilizationRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves
    ) public pure returns (uint256) {
        // Utilization rate is 0 when there are no borrows
        if (borrows == 0) {
            return 0;
        }

        return (borrows * WAD) / (cash + borrows - reserves);
    }

    function getBorrowRateWithUpdate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves
    ) public returns (uint256 borrowRate) {
        uint256 util = utilizationRate(cash, borrows, reserves);
        RatesConfiguration memory config = ratesConfig;
        uint256 vertexPoint = config.vertexStartingPoint;

        bool belowVertex = (util <= vertexPoint);

        if (belowVertex) {
            unchecked {
                borrowRate = getNormalInterestRate(util);
            }
        } else {
            /// We know this will not underflow or overflow because of Interest Rate Model configurations
            unchecked {
                borrowRate = (getVertexInterestRate(util - vertexPoint) +
                    getNormalInterestRate(vertexPoint));
            }
        }

        DynamicRatesData storage currentInfo = currentRates;

        if (block.timestamp >= currentInfo.nextUpdateTimestamp){
            
            // If the vertex multiplier is already at its minimum,
            // and would decrease more, can break here
            if (currentInfo.vertexMultiplier == WAD && util < config.increaseThreshold) {
                currentInfo.nextUpdateTimestamp = uint128(block.timestamp);
                return borrowRate;
            }

            if (belowVertex){
                _updateRatesBelowVertex(currentInfo, config, util);
                currentInfo.nextUpdateTimestamp = uint128(block.timestamp);
                return borrowRate;
            }

            _updateRatesAboveVertex(currentInfo, config, util);
            currentInfo.nextUpdateTimestamp = uint128(block.timestamp);
        }
    }

    /// @notice Calculates the current borrow rate per compound
    /// @param cash The amount of cash in the market
    /// @param borrows The amount of borrows in the market
    /// @param reserves The amount of reserves in the market
    /// @return The borrow rate percentage per second (scaled by 1e18)
    function getBorrowRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves
    ) public view returns (uint256) {
        uint256 util = utilizationRate(cash, borrows, reserves);
        uint256 vertexPoint = ratesConfig.vertexStartingPoint;

        if (util <= vertexPoint) {
            unchecked {
                return getNormalInterestRate(util);
            }
        }

        /// We know this will not underflow or overflow because of Interest Rate Model configurations
        unchecked {
            return (getVertexInterestRate(util - vertexPoint) +
                getNormalInterestRate(vertexPoint));
        }
    }

    /// @notice Calculates the current supply rate per compound
    /// @param cash The amount of cash in the market
    /// @param borrows The amount of borrows in the market
    /// @param reserves The amount of reserves in the market
    /// @param interestFee The current interest rate reserve factor for the market
    /// @return The supply rate percentage per second (scaled by 1e18)
    function getSupplyRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves,
        uint256 interestFee
    ) public view returns (uint256) {
        /// RateToPool = (borrowRate * oneMinusReserveFactor) / WAD;
        uint256 rateToPool = (getBorrowRate(cash, borrows, reserves) *
            (WAD - interestFee)) / WAD;

        /// Supply Rate = (utilizationRate * rateToPool) / WAD;
        return
            (utilizationRate(cash, borrows, reserves) * rateToPool) /
            WAD;
    }

    /// @notice Calculates the current borrow rate per year
    /// @param cash The amount of cash in the market
    /// @param borrows The amount of borrows in the market
    /// @param reserves The amount of reserves in the market
    /// @return The borrow rate percentage per second (scaled by 1e18)
    function getBorrowRatePerYear(
        uint256 cash,
        uint256 borrows,
        uint256 reserves
    ) external view returns (uint256) {
        return
            SECONDS_PER_YEAR *
            (getBorrowRate(cash, borrows, reserves) / INTEREST_COMPOUND_RATE);
    }

    /// @notice Calculates the current supply rate per year
    /// @param cash The amount of cash in the market
    /// @param borrows The amount of borrows in the market
    /// @param reserves The amount of reserves in the market
    /// @param interestFee The current interest rate reserve factor for the market
    /// @return The supply rate percentage per second (scaled by 1e18)
    function getSupplyRatePerYear(
        uint256 cash,
        uint256 borrows,
        uint256 reserves,
        uint256 interestFee
    ) external view returns (uint256) {
        return
            SECONDS_PER_YEAR *
            (getSupplyRate(cash, borrows, reserves, interestFee) /
                INTEREST_COMPOUND_RATE);
    }

    /// @notice Returns the rate at which interest compounds, in seconds
    function compoundRate() external pure returns (uint256) {
        return INTEREST_COMPOUND_RATE;
    }

    /// @notice Calculates the interest rate for `util` market utilization
    /// @param util The utilization rate of the market
    /// @return Returns the calculated interest rate
    function getNormalInterestRate(
        uint256 util
    ) internal view returns (uint256) {
        return (util * ratesConfig.baseInterestRate) / WAD;
    }

    /// @notice Calculates the interest rate under `jump` conditions,
    ///         e.g. `util` > `vertex ` based on market utilization
    /// @param util The utilization rate of the market above `vertex`
    /// @return Returns the calculated excess interest rate
    function getVertexInterestRate(
        uint256 util
    ) internal view returns (uint256) {
        return (util * ratesConfig.vertexInterestRate) / WAD;
    }

    /// INTERNAL FUNCTIONS ///

    function _updateRatesBelowVertex(
        DynamicRatesData storage currentInfo, 
        RatesConfiguration memory config,
        uint256 util
    ) internal {
        uint256 newRate;
        // Calculate decay rate
        uint256 decay = currentInfo.vertexMultiplier * config.decayRate;

        if (util <= config.decreaseThresholdMax) {
            newRate = ((currentInfo.vertexMultiplier * WAD) / config.adjustmentVelocity) - decay;
            if (newRate < WAD) {
                currentInfo.vertexMultiplier = uint128(WAD);
                return;
            }

            // Update and return with decay rate applied.
            currentInfo.vertexMultiplier = uint128(newRate);
            return;
        }

        newRate = (currentInfo.vertexMultiplier * 
        ((config.adjustmentVelocity * WAD) / 
        _calculateNegativeCurveValue(
            util, 
            config.increaseThreshold, 
            config.increaseThresholdMax
        ))) - decay;

        if (newRate < WAD) {
            currentInfo.vertexMultiplier = uint128(WAD);
            return;
        }

        // Update and return with adjustment and decay rate applied.
        currentInfo.vertexMultiplier = uint128(newRate);
    }

    function _updateRatesAboveVertex(
        DynamicRatesData storage currentInfo, 
        RatesConfiguration memory config,
        uint256 util
    ) internal {
        uint256 newRate;
        // Calculate decay rate
        uint256 decay = currentInfo.vertexMultiplier * config.decayRate;

        if (util < config.increaseThreshold) {
            newRate = currentInfo.vertexMultiplier - decay;
            // Check if decay rate sends new rate below 1.
            if (newRate < WAD) {
                currentInfo.vertexMultiplier = uint128(WAD);
                return;
            }

            // Update and return with decay rate applied.
            currentInfo.vertexMultiplier = uint128(newRate);
            return;
        }

        newRate = (currentInfo.vertexMultiplier * 
        (config.adjustmentVelocity * 
        _calculatePositiveCurveValue(
            util, 
            config.increaseThreshold, 
            config.increaseThresholdMax
        )) / WAD) - decay;

        // Its theorectically possible for the new rate to be below 1 due to decay,
        // so we still need to check.
        if (newRate < WAD) {
            currentInfo.vertexMultiplier = uint128(WAD);
            return;
        }
        
        // Update and return with adjustment and decay rate applied.
        currentInfo.vertexMultiplier = uint128(newRate);
    }

    function _calculatePositiveCurveValue(uint256 current, uint256 start, uint256 end) internal pure returns (uint256) {
        if (current >= end) {
            return WAD;
        }

        // Because slope values should be between [1, WAD],
        // we know multiplying by WAD again will not cause overflows
        unchecked {
            current = current * WAD;
            start = start * WAD;
            end = end * WAD;
        }
    
        return (current - start) / (end - start);
    }

    function _calculateNegativeCurveValue(uint256 current, uint256 start, uint256 end) internal pure returns (uint256) {
        if (current <= end) {
            return WAD;
        }

        // Because slope values should be between [1, WAD],
        // we know multiplying by WAD again will not cause overflows
        unchecked{
            current = current * WAD;
            start = start * WAD;
            end = end * WAD;
        }
        
        return (start - current) / (start - end);
    }

    /// @dev Internal helper function for easily converting between scalars
    function _bpToWad(uint256 value) internal pure returns (uint256 result) {
        assembly {
            result := mul(value, 100000000000000)
        }
    }

    function _updateDynamicInterestRateModel(
        uint256 baseRatePerYear,
        uint256 vertexRatePerYear,
        uint256 vertexUtilizationStart,
        uint256 adjustmentRate,
        uint256 adjustmentVelocity,
        uint256 decayRate,
        bool vertexReset
    ) internal {

        // Convert the parameters from basis points to `WAD` format,
        // while inefficient we want to minimize potential human error
        // as much as possible, even if it costs a bit extra gas on config
        baseRatePerYear = _bpToWad(baseRatePerYear);
        vertexRatePerYear = _bpToWad(vertexRatePerYear);
        vertexUtilizationStart = _bpToWad(vertexUtilizationStart);
        adjustmentRate = _bpToWad(adjustmentRate);
        // This is a multiplier/divisor so it needs to be on top of the base value (WAD)
        adjustmentVelocity = _bpToWad(adjustmentVelocity) + WAD;
        decayRate = _bpToWad(decayRate);

        if (adjustmentVelocity > MAX_VERTEX_ADJUSTMENT_VELOCITY) {
            revert DynamicInterestRateModel__InvalidAdjustmentVelocity();
        }

        if (adjustmentRate > MAX_VERTEX_ADJUSTMENT_RATE || adjustmentRate < MIN_VERTEX_ADJUSTMENT_RATE) {
            revert DynamicInterestRateModel__InvalidAdjustmentRate();
        }

        if (decayRate > MAX_VERTEX_DECAY_RATE) {
            revert DynamicInterestRateModel__InvalidDecayRate();
        }

        DynamicRatesData storage currentInfo = currentRates;
        RatesConfiguration storage config = ratesConfig;

        config.baseInterestRate =
            (INTEREST_COMPOUND_RATE * baseRatePerYear * WAD) /
            (SECONDS_PER_YEAR * vertexUtilizationStart);
        config.vertexInterestRate =
            (INTEREST_COMPOUND_RATE * vertexRatePerYear) /
            SECONDS_PER_YEAR;

        config.vertexStartingPoint = vertexUtilizationStart;
        config.adjustmentRate = adjustmentRate;
        currentInfo.nextUpdateTimestamp =  uint128(block.timestamp + config.adjustmentRate);
        if (vertexReset) {
            currentInfo.vertexMultiplier = uint128(WAD);
        }
        config.decayRate = decayRate;

        uint256 thresholdLength = (WAD - vertexUtilizationStart) / 2;
        config.increaseThreshold = vertexUtilizationStart + thresholdLength;
        config.increaseThresholdMax = WAD;

        config.decreaseThreshold = vertexUtilizationStart;
        config.decreaseThresholdMax = vertexUtilizationStart - thresholdLength;

        RatesConfiguration memory cachedConfig = config;

        emit NewDynamicInterestRateModel(
            cachedConfig.baseInterestRate, // base rate
            cachedConfig.vertexInterestRate, // vertex base rate
            vertexUtilizationStart, // Vertex utilization rate start
            adjustmentRate, // Adjustment rate
            adjustmentVelocity, // Adjustment velocity 
            decayRate, // Decay rate
            cachedConfig.increaseThreshold, // Vertex increase threshold
            WAD, // Vertex increase threshold max
            cachedConfig.decreaseThreshold, // Vertex decrease threshold
            cachedConfig.decreaseThresholdMax, // // Vertex decrease threshold max
            vertexReset // Was vertex multiplier reset
        );
    }
}
