// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";

contract InterestRateModel {
    /// CONSTANTS ///

    uint256 private constant BASE = 1e18;
    /// Unix time has 31,536,000 seconds per year 
    /// All my homies hate leap seconds and leap years
    uint256 public constant secondsPerYear = 31536000;

    /// @notice Indicator that this is an InterestRateModel contract
    ///         (for inspection)
    bool public constant isInterestRateModel = true;

    ICentralRegistry public immutable centralRegistry;

    /// STORAGE ///

    uint256 public multiplierPerSecond;
    uint256 public baseRatePerSecond;
    uint256 public jumpMultiplierPerSecond;
    uint256 public kink;

    /// EVENTS ///

    event NewInterestRateModel(
        uint256 baseRatePerSecond,
        uint256 multiplierPerSecond,
        uint256 jumpMultiplierPerSecond,
        uint256 kink
    );

    /// MODIFIERS ///

    modifier onlyElevatedPermissions() {
        require(
            centralRegistry.hasElevatedPermissions(msg.sender),
            "InterestRateModel: UNAUTHORIZED"
        );
        _;
    }

    /// CONSTRUCTOR ///

    /// @notice Construct an interest rate model
    /// @param baseRatePerYear The approximate target base APR,
    ///                        as a mantissa (scaled by BASE)
    /// @param multiplierPerYear The rate of increase in interest rate by
    ///                          utilization rate (scaled by BASE)
    /// @param jumpMultiplierPerYear The multiplierPerSecond after hitting
    ///                              `kink_` utilization rate
    /// @param kink_ The utilization point at which the jump multiplier
    ///              is applied
    constructor(
        ICentralRegistry centralRegistry_,
        uint256 baseRatePerYear,
        uint256 multiplierPerYear,
        uint256 jumpMultiplierPerYear,
        uint256 kink_
    ) {

        require(
            ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            ),
            "InterestRateModel: invalid central registry"
        );

        centralRegistry = centralRegistry_;

        baseRatePerSecond = baseRatePerYear / secondsPerYear;
        multiplierPerSecond =
            (multiplierPerYear * BASE) /
            (secondsPerYear * kink_);
        jumpMultiplierPerSecond = jumpMultiplierPerYear / secondsPerYear;
        kink = kink_;

        emit NewInterestRateModel(
            baseRatePerSecond,
            multiplierPerSecond,
            jumpMultiplierPerSecond,
            kink
        );
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Update the parameters of the interest rate model
    ///         (only callable by Curvance DAO elevated permissions, i.e. Timelock)
    /// @param baseRatePerYear The approximate target base APR,
    ///                        as a mantissa (scaled by BASE)
    /// @param multiplierPerYear The rate of increase in interest rate by
    ///                          utilization rate (scaled by BASE)
    /// @param jumpMultiplierPerYear The multiplierPerSecond after hitting
    ///                              `kink_` utilization rate
    /// @param kink_ The utilization point at which the jump multiplier
    ///              is applied
    function updateInterestRateModel(
        uint256 baseRatePerYear,
        uint256 multiplierPerYear,
        uint256 jumpMultiplierPerYear,
        uint256 kink_
    ) external onlyElevatedPermissions {

        baseRatePerSecond = baseRatePerYear / secondsPerYear;
        multiplierPerSecond =
            (multiplierPerYear * BASE) /
            (secondsPerYear * kink_);
        jumpMultiplierPerSecond = jumpMultiplierPerYear / secondsPerYear;
        kink = kink_;

        emit NewInterestRateModel(
            baseRatePerSecond,
            multiplierPerSecond,
            jumpMultiplierPerSecond,
            kink
        );
    }

    /// PUBLIC FUNCTIONS ///

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

    /// @notice Calculates the current borrow rate per second
    /// @param cash The amount of cash in the market
    /// @param borrows The amount of borrows in the market
    /// @param reserves The amount of reserves in the market
    /// @return The borrow rate percentage per second as a mantissa
    ///         (scaled by 1e18)
    function getBorrowRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves
    ) public view returns (uint256) {
        uint256 util = utilizationRate(cash, borrows, reserves);

        if (util <= kink) {
            unchecked {
                return ((util * multiplierPerSecond) / BASE) + baseRatePerSecond;
            }
        }

        /// We know this will not underflow or overflow because of Interest Rate Model configurations
        unchecked {
            uint256 normalRate = ((kink * multiplierPerSecond) / BASE) +
            baseRatePerSecond;
            /// normalRate = ((kink * multiplierPerSecond) / BASE) + baseRatePerSecond;
            /// jumpRate = ((util - kink) * jumpMultiplierPerSecond / Base)
            /// BorrowRate = jumpRate + normalRate
            return (((util - kink) * jumpMultiplierPerSecond) / BASE) + normalRate;
        }
    }

    /// @notice Calculates the current supply rate per second
    /// @param cash The amount of cash in the market
    /// @param borrows The amount of borrows in the market
    /// @param reserves The amount of reserves in the market
    /// @param reserveFactorMantissa The current reserve factor for the market
    /// @return The supply rate percentage per second as a mantissa
    ///         (scaled by BASE)
    function getSupplyRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves,
        uint256 reserveFactorMantissa
    ) public view returns (uint256) {
        /// RateToPool = (borrowRate * oneMinusReserveFactor) / BASE;
        uint256 rateToPool = (getBorrowRate(cash, borrows, reserves) * (BASE - reserveFactorMantissa)) / BASE;

        /// Supply Rate = (utilizationRate * rateToPool) / BASE;
        return (utilizationRate(cash, borrows, reserves) * rateToPool) / BASE;
    }

    
}
