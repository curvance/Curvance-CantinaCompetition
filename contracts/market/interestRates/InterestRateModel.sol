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
    uint256 public jumpMultiplierPerSecond;
    uint256 public rateCurveKink;

    /// EVENTS ///

    event NewInterestRateModel(
        uint256 multiplierPerSecond,
        uint256 jumpMultiplierPerSecond,
        uint256 rateCurveKink
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
    /// @param multiplierPerYear The rate of increase in interest rate by
    ///                          utilization rate (scaled by BASE)
    /// @param jumpMultiplierPerYear The multiplierPerSecond after hitting
    ///                              `kink_` utilization rate
    /// @param kink The utilization point at which the jump multiplier
    ///              is applied
    constructor(
        ICentralRegistry centralRegistry_,
        uint256 multiplierPerYear,
        uint256 jumpMultiplierPerYear,
        uint256 kink
    ) {

        require(
            ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            ),
            "InterestRateModel: invalid central registry"
        );

        centralRegistry = centralRegistry_;

        multiplierPerSecond =
            (multiplierPerYear * BASE) /
            (secondsPerYear * kink);
        jumpMultiplierPerSecond = jumpMultiplierPerYear / secondsPerYear;
        rateCurveKink = kink;

        emit NewInterestRateModel(
            multiplierPerSecond,
            jumpMultiplierPerSecond,
            kink
        );
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Update the parameters of the interest rate model
    ///         (only callable by Curvance DAO elevated permissions, i.e. Timelock)
    /// @param multiplierPerYear The rate of increase in interest rate by
    ///                          utilization rate (scaled by BASE)
    /// @param jumpMultiplierPerYear The multiplierPerSecond after hitting
    ///                              `kink` utilization rate
    /// @param kink The utilization point at which the jump multiplier
    ///             is applied
    function updateInterestRateModel(
        uint256 multiplierPerYear,
        uint256 jumpMultiplierPerYear,
        uint256 kink
    ) external onlyElevatedPermissions {

        multiplierPerSecond =
            (multiplierPerYear * BASE) /
            (secondsPerYear * kink);
        jumpMultiplierPerSecond = jumpMultiplierPerYear / secondsPerYear;
        rateCurveKink = kink;

        emit NewInterestRateModel(
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

        if (util <= rateCurveKink) {
            unchecked {
                return getNormalInterestRate(util);
            }
        }

        /// We know this will not underflow or overflow because of Interest Rate Model configurations
        unchecked {
            return(getJumpInterestRate(util - rateCurveKink) + getNormalInterestRate(rateCurveKink));
        }
    }

    /// @notice Calculates the current supply rate per second
    /// @param cash The amount of cash in the market
    /// @param borrows The amount of borrows in the market
    /// @param reserves The amount of reserves in the market
    /// @param marketReservesInterestFee The current interest rate reserve factor for the market
    /// @return The supply rate percentage per second as a mantissa
    ///         (scaled by BASE)
    function getSupplyRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves,
        uint256 marketReservesInterestFee
    ) public view returns (uint256) {
        /// RateToPool = (borrowRate * oneMinusReserveFactor) / BASE;
        uint256 rateToPool = (getBorrowRate(cash, borrows, reserves) * (BASE - marketReservesInterestFee)) / BASE;

        /// Supply Rate = (utilizationRate * rateToPool) / BASE;
        return (utilizationRate(cash, borrows, reserves) * rateToPool) / BASE;
    }

    /// Internal Functions ///

    /**
    * @notice Calculates the interest rate for `util` market utilization
    * @param util The utilization rate of the market
    * @return Returns the calculated interest rate
    */
    function getNormalInterestRate(uint256 util) internal view returns (uint256){
        return (util * multiplierPerSecond) / BASE;
    }

    /// @notice Calculates the interest rate under `jump` conditions E.G. `util` > `kink ` based on market utilization
    /// @param util The utilization rate of the market above `kink`
    /// @return Returns the calculated excess interest rate
    function getJumpInterestRate(uint256 util) internal view returns (uint256){
        return (util * jumpMultiplierPerSecond) / BASE;
    }

}
