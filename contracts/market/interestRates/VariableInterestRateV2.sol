// SPDX-License-Identifier: ISC
pragma solidity ^0.8.17;

// Adapted from Frax Finance's Fraxlend model
// Original Author: Drake Evans: https://github.com/DrakeEvans

contract VariableInterestRate {
    /// TYPES ///

    struct CurrentRateInfo {
        uint32 lastBlock;
        uint32 feeToProtocolRate; // Fee amount 1e5 precision
        uint64 lastTimestamp;
        uint64 ratePerSec;
        uint64 fullUtilizationRate;
    }

    /// CONSTANTS ///

    /// @notice The precision of interest rate calculations
    uint256 public constant BASE = 1e18; // 18 decimals

    // Utilization Settings
    /// @notice precision of utilization calculations
    uint256 public constant UTIL_PREC = 1e5; // 5 decimals
    /// @notice The minimum utilization wherein no adjustment to full utilization and vertex rates occurs
    uint256 public immutable MIN_TARGET_UTIL;
    /// @notice The maximum utilization wherein no adjustment to full utilization and vertex rates occurs
    uint256 public immutable MAX_TARGET_UTIL;
    /// @notice The utilization at which the slope increases
    uint256 public immutable VERTEX_UTILIZATION;

    // Interest Rate Settings (all rates are per second), 365.24 days per year
    /// @notice The minimum interest rate (per second) when utilization is 100%
    uint256 public immutable MIN_FULL_UTIL_RATE; // 18 decimals
    /// @notice The maximum interest rate (per second) when utilization is 100%
    uint256 public immutable MAX_FULL_UTIL_RATE; // 18 decimals
    /// @notice The interest rate (per second) when utilization is 0%
    uint256 public immutable ZERO_UTIL_RATE; // 18 decimals
    /// @notice The interest rate half life in seconds, determines rate of adjustments to rate curve
    uint256 public immutable RATE_HALF_LIFE; // 1 decimals
    /// @notice The percent of the delta between max and min
    uint256 public immutable VERTEX_RATE_PERCENT; // 18 decimals

    /// STORAGE ///

    CurrentRateInfo public currentRateInfo;

    /// CONSTURCTOR ///

    /// @param vertexUtilization The utilization at which the slope increases
    /// @param vertexRatePercentOfDelta The percent of the delta between
    ///                                 max and min, defines vertex rate
    /// @param minUtil The minimum utilization wherein no adjustment
    ///                to full utilization and vertex rates occurs
    /// @param maxUtil The maximum utilization wherein no adjustment
    ///                to full utilization and vertex rates occurs
    /// @param zeroUtilizationRate The interest rate (per second) when
    ///                            utilization is 0%
    /// @param minFullUtilizationRate The minimum interest rate at
    ///                               100% utilization
    /// @param maxFullUtilizationRate The maximum interest rate at
    ///                               100% utilization
    /// @param rateHalfLife The half life parameter for interest rate
    ///                     adjustments
    constructor(
        uint256 vertexUtilization,
        uint256 vertexRatePercentOfDelta,
        uint256 minUtil,
        uint256 maxUtil,
        uint256 zeroUtilizationRate,
        uint256 minFullUtilizationRate,
        uint256 maxFullUtilizationRate,
        uint256 rateHalfLife
    ) {
        MIN_TARGET_UTIL = minUtil;
        MAX_TARGET_UTIL = maxUtil;
        VERTEX_UTILIZATION = vertexUtilization;
        ZERO_UTIL_RATE = zeroUtilizationRate;
        MIN_FULL_UTIL_RATE = minFullUtilizationRate;
        MAX_FULL_UTIL_RATE = maxFullUtilizationRate;
        RATE_HALF_LIFE = rateHalfLife;
        VERTEX_RATE_PERCENT = vertexRatePercentOfDelta;
    }

    /// @notice Calculates the utilization rate of the market:
    ///         `borrows / (cash + borrows - reserves)`
    /// @param cash The amount of cash in the market
    /// @param borrows The amount of borrows in the market
    /// @param reserves The amount of reserves in the market (currently unused)
    /// @return The utilization rate as a mantissa between [0, BASE]
    function utilizationRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves
    ) public pure returns (uint256) {
        // Utilization rate is 0 when there are no borrows
        if (borrows == 0) {
            return 0;
        }

        return (borrows * BASE) / (cash + borrows - reserves);
    }

    /// @notice The ```getFullUtilizationInterest``` function calculate
    ///         the new maximum interest rate,
    ///         i.e. rate when utilization is 100%
    /// @dev Given in interest per second
    /// @param deltaTime The elapsed time since last update given in seconds
    /// @param utilization The utilization %, given with 5 decimals of precision
    /// @param fullUtilizationInterest The interest value when utilization is 100%,
    ///                                 given with 18 decimals of precision
    /// @return newFullUtilizationInterest The new maximum interest rate
    function getFullUtilizationInterest(
        uint256 deltaTime,
        uint256 utilization,
        uint64 fullUtilizationInterest
    ) internal view returns (uint64 newFullUtilizationInterest) {
        if (utilization < MIN_TARGET_UTIL) {
            // 18 decimals
            uint256 deltaUtilization = ((MIN_TARGET_UTIL - utilization) *
                1e18) / MIN_TARGET_UTIL;
            // 36 decimals
            uint256 decayGrowth = (RATE_HALF_LIFE * 1e36) +
                (deltaUtilization * deltaUtilization * deltaTime);
            // 18 decimals
            newFullUtilizationInterest = uint64(
                (fullUtilizationInterest * (RATE_HALF_LIFE * 1e36)) /
                    decayGrowth
            );
        } else if (utilization > MAX_TARGET_UTIL) {
            // 18 decimals
            uint256 deltaUtilization = ((utilization - MAX_TARGET_UTIL) *
                1e18) / (UTIL_PREC - MAX_TARGET_UTIL);
            // 36 decimals
            uint256 decayGrowth = (RATE_HALF_LIFE * 1e36) +
                (deltaUtilization * deltaUtilization * deltaTime);
            // 18 decimals
            newFullUtilizationInterest = uint64(
                (fullUtilizationInterest * decayGrowth) /
                    (RATE_HALF_LIFE * 1e36)
            );
        } else {
            newFullUtilizationInterest = fullUtilizationInterest;
        }
        if (newFullUtilizationInterest > MAX_FULL_UTIL_RATE) {
            newFullUtilizationInterest = uint64(MAX_FULL_UTIL_RATE);
        } else if (newFullUtilizationInterest < MIN_FULL_UTIL_RATE) {
            newFullUtilizationInterest = uint64(MIN_FULL_UTIL_RATE);
        }
    }

    /// @notice The ```getNewRate``` function calculates interest rates
    ///         using two linear functions f(utilization)
    /// @param deltaTime The elapsed time since last update, given in seconds
    /// @param utilization The utilization %, given with 5 decimals of precision
    /// @param oldFullUtilizationInterest The interest value when utilization
    ///                                   is 100%, given with 18 decimals of
    ///                                   precision
    /// @return newRatePerSec The new interest rate, 18 decimals of precision
    /// @return newFullUtilizationInterest The new max interest rate,
    ///                                    18 decimals of precision
    function getNewRate(
        uint256 deltaTime,
        uint256 utilization,
        uint64 oldFullUtilizationInterest
    )
        external
        view
        returns (uint64 newRatePerSec, uint64 newFullUtilizationInterest)
    {
        newFullUtilizationInterest = getFullUtilizationInterest(
            deltaTime,
            utilization,
            oldFullUtilizationInterest
        );

        // vertexInterest is calculated as the percentage of the delta between min and max interest
        uint256 vertexInterest = (((newFullUtilizationInterest -
            ZERO_UTIL_RATE) * VERTEX_RATE_PERCENT) / BASE) + ZERO_UTIL_RATE;
        if (utilization < VERTEX_UTILIZATION) {
            // For readability, the following formula is equivalent to:
            // uint256 _slope = ((vertexInterest - ZERO_UTIL_RATE) * UTIL_PREC) / VERTEX_UTILIZATION;
            // newRatePerSec = uint64(ZERO_UTIL_RATE + ((utilization * _slope) / UTIL_PREC));

            // 18 decimals
            newRatePerSec = uint64(
                ZERO_UTIL_RATE +
                    (utilization * (vertexInterest - ZERO_UTIL_RATE)) /
                    VERTEX_UTILIZATION
            );
        } else {
            // For readability, the following formula is equivalent to:
            // uint256 _slope = (((newFullUtilizationInterest - vertexInterest) * UTIL_PREC) / (UTIL_PREC - VERTEX_UTILIZATION));
            // newRatePerSec = uint64(vertexInterest + (((utilization - VERTEX_UTILIZATION) * _slope) / UTIL_PREC));

            // 18 decimals
            newRatePerSec = uint64(
                vertexInterest +
                    ((utilization - VERTEX_UTILIZATION) *
                        (newFullUtilizationInterest - vertexInterest)) /
                    (UTIL_PREC - VERTEX_UTILIZATION)
            );
        }
    }
}
