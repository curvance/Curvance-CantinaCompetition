// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";

contract InterestRateModel {
    
    /// CONSTANTS ///

    /// Unix time has 31,536,000 seconds per year 
    /// All my homies hate leap seconds and leap years
    uint256 private constant SECONDS_PER_YEAR = 31536000;
    /// @notice Scalar for math
    uint256 private constant EXP_SCALE = 1e18;
    /// @notice Rate at which interest is compounded, in seconds
    uint256 internal constant INTEREST_COMPOUND_RATE = 300;
    /// @notice For external contract's to call for validation
    bool public constant IS_INTEREST_RATE_MODEL = true;
    /// @notice Curvance DAO hub
    ICentralRegistry public immutable centralRegistry;

    /// STORAGE ///

    uint256 public baseRate; // Rate interest grows
    uint256 public vertexRate; // boosted rate interest grows
    // Utilization rate point when jump multiplier kicks in
    uint256 public vertexStart; 

    /// EVENTS ///

    event NewInterestRateModel(
        uint256 baseRate,
        uint256 vertexRate,
        uint256 vertexUtilizationStart
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
    /// @param baseRatePerYear The rate of increase in interest rate by
    ///                        utilization rate (scaled by EXP_SCALE)
    /// @param vertexRatePerYear The multiplierPerSecond after hitting
    ///                              `vertex_` utilization rate
    /// @param vertexUtilizationStart The utilization point at which the vertex rate
    ///               is applied
    constructor(
        ICentralRegistry centralRegistry_,
        uint256 baseRatePerYear,
        uint256 vertexRatePerYear,
        uint256 vertexUtilizationStart
    ) {

        require(
            ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            ),
            "InterestRateModel: invalid central registry"
        );

        centralRegistry = centralRegistry_;

        baseRate =
            (INTEREST_COMPOUND_RATE * baseRatePerYear * EXP_SCALE) /
            (SECONDS_PER_YEAR * vertexUtilizationStart);
        vertexRate = (INTEREST_COMPOUND_RATE * vertexRatePerYear) / SECONDS_PER_YEAR;
        vertexStart = vertexUtilizationStart;

        emit NewInterestRateModel(
            baseRate,
            vertexRate,
            vertexUtilizationStart
        );
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Update the parameters of the interest rate model
    ///         (only callable by Curvance DAO elevated permissions, i.e. Timelock)
    /// @param baseRatePerYear The rate of increase in interest rate by
    ///                          utilization rate (scaled by EXP_SCALE)
    /// @param vertexRatePerYear The multiplierPerSecond after hitting
    ///                              `vertex` utilization rate
    /// @param vertexUtilizationStart The utilization point at which the jump multiplier
    ///                               is applied
    function updateInterestRateModel(
        uint256 baseRatePerYear,
        uint256 vertexRatePerYear,
        uint256 vertexUtilizationStart
    ) external onlyElevatedPermissions {

        baseRate =
            (INTEREST_COMPOUND_RATE * baseRatePerYear * EXP_SCALE) /
            (SECONDS_PER_YEAR * vertexUtilizationStart);
        vertexRate = (INTEREST_COMPOUND_RATE * vertexRatePerYear) / SECONDS_PER_YEAR;
        vertexStart = vertexUtilizationStart;

        emit NewInterestRateModel(
            baseRate,
            vertexRate,
            vertexUtilizationStart
        );
    }

    /// PUBLIC FUNCTIONS ///

    /// @notice Calculates the utilization rate of the market:
    ///         `borrows / (cash + borrows - reserves)`
    /// @param cash The amount of cash in the market
    /// @param borrows The amount of borrows in the market
    /// @param reserves The amount of reserves in the market
    /// @return The utilization rate between [0, EXP_SCALE]
    function utilizationRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves
    ) public pure returns (uint256) {
        // Utilization rate is 0 when there are no borrows
        if (borrows == 0) {
            return 0;
        }

        return (borrows * EXP_SCALE) / (cash + borrows - reserves);
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

        if (util <= vertexStart) {
            unchecked {
                return getNormalInterestRate(util);
            }
        }

        /// We know this will not underflow or overflow because of Interest Rate Model configurations
        unchecked {
            return(getVertexInterestRate(util - vertexStart) + getNormalInterestRate(vertexStart));
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
        /// RateToPool = (borrowRate * oneMinusReserveFactor) / EXP_SCALE;
        uint256 rateToPool = (getBorrowRate(cash, borrows, reserves) * (EXP_SCALE - interestFee)) / EXP_SCALE;

        /// Supply Rate = (utilizationRate * rateToPool) / EXP_SCALE;
        return (utilizationRate(cash, borrows, reserves) * rateToPool) / EXP_SCALE;
    }


    /// @notice Calculates the current borrow rate per year
    /// @param cash The amount of cash in the market
    /// @param borrows The amount of borrows in the market
    /// @param reserves The amount of reserves in the market
    /// @return The borrow rate percentage per second (scaled by 1e18)
    function getBorrowRatePerYear(
        uint256 cash,
        uint256 borrows,
        uint256 reserves) external view returns (uint256) {
            return 
                SECONDS_PER_YEAR * 
                (getBorrowRate(cash, borrows, reserves) / 
                INTEREST_COMPOUND_RATE);
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
    )  external view returns (uint256) {
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
    function getNormalInterestRate(uint256 util) internal view returns (uint256){
        return (util * baseRate) / EXP_SCALE;
    }

    /// @notice Calculates the interest rate under `jump` conditions E.G. `util` > `vertex ` based on market utilization
    /// @param util The utilization rate of the market above `vertex`
    /// @return Returns the calculated excess interest rate
    function getVertexInterestRate(uint256 util) internal view returns (uint256){
        return (util * vertexRate) / EXP_SCALE;
    }

}
