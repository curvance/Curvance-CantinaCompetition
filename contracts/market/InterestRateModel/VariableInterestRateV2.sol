// SPDX-License-Identifier: ISC
pragma solidity ^0.8.17;

// Adapted from Frax Finance's Fraxlend model
// Original Author: Drake Evans: https://github.com/DrakeEvans

contract VariableInterestRate {
    // Utilization Settings
    /// @notice The minimum utilization wherein no adjustment to full utilization and vertex rates occurs
    uint256 public immutable MIN_TARGET_UTIL;
    /// @notice The maximum utilization wherein no adjustment to full utilization and vertex rates occurs
    uint256 public immutable MAX_TARGET_UTIL;
    /// @notice The utilization at which the slope increases
    uint256 public immutable VERTEX_UTILIZATION;
    /// @notice precision of utilization calculations
    uint256 public constant UTIL_PREC = 1e5; // 5 decimals

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
    /// @notice The precision of interest rate calculations
    uint256 public constant BASE = 1e18; // 18 decimals

    struct CurrentRateInfo {
        uint32 lastBlock;
        uint32 feeToProtocolRate; // Fee amount 1e5 precision
        uint64 lastTimestamp;
        uint64 ratePerSec;
        uint64 fullUtilizationRate;
    }

    CurrentRateInfo public currentRateInfo;

    /// @notice The ```constructor``` function
    /// @param _vertexUtilization The utilization at which the slope increases
    /// @param _vertexRatePercentOfDelta The percent of the delta between max and min, defines vertex rate
    /// @param _minUtil The minimum utilization wherein no adjustment to full utilization and vertex rates occurs
    /// @param _maxUtil The maximum utilization wherein no adjustment to full utilization and vertex rates occurs
    /// @param _zeroUtilizationRate The interest rate (per second) when utilization is 0%
    /// @param _minFullUtilizationRate The minimum interest rate at 100% utilization
    /// @param _maxFullUtilizationRate The maximum interest rate at 100% utilization
    /// @param _rateHalfLife The half life parameter for interest rate adjustments
    constructor(
        uint256 _vertexUtilization,
        uint256 _vertexRatePercentOfDelta,
        uint256 _minUtil,
        uint256 _maxUtil,
        uint256 _zeroUtilizationRate,
        uint256 _minFullUtilizationRate,
        uint256 _maxFullUtilizationRate,
        uint256 _rateHalfLife
    ) {
        MIN_TARGET_UTIL = _minUtil;
        MAX_TARGET_UTIL = _maxUtil;
        VERTEX_UTILIZATION = _vertexUtilization;
        ZERO_UTIL_RATE = _zeroUtilizationRate;
        MIN_FULL_UTIL_RATE = _minFullUtilizationRate;
        MAX_FULL_UTIL_RATE = _maxFullUtilizationRate;
        RATE_HALF_LIFE = _rateHalfLife;
        VERTEX_RATE_PERCENT = _vertexRatePercentOfDelta;
    }

    /**
     * @notice Calculates the utilization rate of the market: `borrows / (cash + borrows - reserves)`
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market (currently unused)
     * @return The utilization rate as a mantissa between [0, BASE]
     */
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

    /// @notice The ```getFullUtilizationInterest``` function calculate the new maximum interest rate, i.e. rate when utilization is 100%
    /// @dev Given in interest per second
    /// @param _deltaTime The elapsed time since last update given in seconds
    /// @param _utilization The utilization %, given with 5 decimals of precision
    /// @param _fullUtilizationInterest The interest value when utilization is 100%, given with 18 decimals of precision
    /// @return _newFullUtilizationInterest The new maximum interest rate
    function getFullUtilizationInterest(
        uint256 _deltaTime,
        uint256 _utilization,
        uint64 _fullUtilizationInterest
    ) internal view returns (uint64 _newFullUtilizationInterest) {
        if (_utilization < MIN_TARGET_UTIL) {
            // 18 decimals
            uint256 _deltaUtilization = ((MIN_TARGET_UTIL - _utilization) *
                1e18) / MIN_TARGET_UTIL;
            // 36 decimals
            uint256 _decayGrowth = (RATE_HALF_LIFE * 1e36) +
                (_deltaUtilization * _deltaUtilization * _deltaTime);
            // 18 decimals
            _newFullUtilizationInterest = uint64(
                (_fullUtilizationInterest * (RATE_HALF_LIFE * 1e36)) /
                    _decayGrowth
            );
        } else if (_utilization > MAX_TARGET_UTIL) {
            // 18 decimals
            uint256 _deltaUtilization = ((_utilization - MAX_TARGET_UTIL) *
                1e18) / (UTIL_PREC - MAX_TARGET_UTIL);
            // 36 decimals
            uint256 _decayGrowth = (RATE_HALF_LIFE * 1e36) +
                (_deltaUtilization * _deltaUtilization * _deltaTime);
            // 18 decimals
            _newFullUtilizationInterest = uint64(
                (_fullUtilizationInterest * _decayGrowth) /
                    (RATE_HALF_LIFE * 1e36)
            );
        } else {
            _newFullUtilizationInterest = _fullUtilizationInterest;
        }
        if (_newFullUtilizationInterest > MAX_FULL_UTIL_RATE) {
            _newFullUtilizationInterest = uint64(MAX_FULL_UTIL_RATE);
        } else if (_newFullUtilizationInterest < MIN_FULL_UTIL_RATE) {
            _newFullUtilizationInterest = uint64(MIN_FULL_UTIL_RATE);
        }
    }

    /// @notice The ```getNewRate``` function calculates interest rates using two linear functions f(utilization)
    /// @param _deltaTime The elapsed time since last update, given in seconds
    /// @param _utilization The utilization %, given with 5 decimals of precision
    /// @param _oldFullUtilizationInterest The interest value when utilization is 100%, given with 18 decimals of precision
    /// @return _newRatePerSec The new interest rate, 18 decimals of precision
    /// @return _newFullUtilizationInterest The new max interest rate, 18 decimals of precision
    function getNewRate(
        uint256 _deltaTime,
        uint256 _utilization,
        uint64 _oldFullUtilizationInterest
    )
        external
        view
        returns (uint64 _newRatePerSec, uint64 _newFullUtilizationInterest)
    {
        _newFullUtilizationInterest = getFullUtilizationInterest(
            _deltaTime,
            _utilization,
            _oldFullUtilizationInterest
        );

        // _vertexInterest is calculated as the percentage of the delta between min and max interest
        uint256 _vertexInterest = (((_newFullUtilizationInterest -
            ZERO_UTIL_RATE) * VERTEX_RATE_PERCENT) / BASE) + ZERO_UTIL_RATE;
        if (_utilization < VERTEX_UTILIZATION) {
            // For readability, the following formula is equivalent to:
            // uint256 _slope = ((_vertexInterest - ZERO_UTIL_RATE) * UTIL_PREC) / VERTEX_UTILIZATION;
            // _newRatePerSec = uint64(ZERO_UTIL_RATE + ((_utilization * _slope) / UTIL_PREC));

            // 18 decimals
            _newRatePerSec = uint64(
                ZERO_UTIL_RATE +
                    (_utilization * (_vertexInterest - ZERO_UTIL_RATE)) /
                    VERTEX_UTILIZATION
            );
        } else {
            // For readability, the following formula is equivalent to:
            // uint256 _slope = (((_newFullUtilizationInterest - _vertexInterest) * UTIL_PREC) / (UTIL_PREC - VERTEX_UTILIZATION));
            // _newRatePerSec = uint64(_vertexInterest + (((_utilization - VERTEX_UTILIZATION) * _slope) / UTIL_PREC));

            // 18 decimals
            _newRatePerSec = uint64(
                _vertexInterest +
                    ((_utilization - VERTEX_UTILIZATION) *
                        (_newFullUtilizationInterest - _vertexInterest)) /
                    (UTIL_PREC - VERTEX_UTILIZATION)
            );
        }
    }
}
