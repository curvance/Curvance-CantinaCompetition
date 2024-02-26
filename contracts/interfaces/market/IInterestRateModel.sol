// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IInterestRateModel {
    /// @notice Calculates the current borrow rate per year,
    ///         with updated vertex multiplier applied.
    /// @param cash The amount of cash in the market.
    /// @param borrows The amount of borrows in the market.
    /// @param reserves The amount of reserves in the market.
    /// @return The borrow rate percentage per year, in `WAD`.
    function getPredictedBorrowRatePerYear(
        uint256 cash,
        uint256 borrows,
        uint256 reserves
    ) external view returns (uint256);
    /// @notice Calculates the current borrow rate per compound,
    ///         and updates the vertex multiplier if necessary.
    /// @param cash The amount of cash in the market.
    /// @param borrows The amount of borrows in the market.
    /// @param reserves The amount of reserves in the market.
    /// @return borrowRate The borrow rate percentage per compound, in `WAD`.
    function getBorrowRateWithUpdate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves
    ) external returns (uint256);
    /// @notice Calculates the current borrow rate per year.
    /// @param cash The amount of cash in the market.
    /// @param borrows The amount of borrows in the market.
    /// @param reserves The amount of reserves in the market.
    /// @return The borrow rate percentage per year, in `WAD`.
    function getBorrowRatePerYear(
        uint256 cash,
        uint256 borrows,
        uint256 reserves
    ) external view returns (uint256);
    /// @notice Calculates the current supply rate per year.
    /// @param cash The amount of cash in the market.
    /// @param borrows The amount of borrows in the market.
    /// @param reserves The amount of reserves in the market.
    /// @param interestFee The current interest rate reserve factor
    ///                    for the market.
    /// @return The supply rate percentage per year, in `WAD`.
    function getSupplyRatePerYear(
        uint256 cash,
        uint256 borrows,
        uint256 reserves,
        uint256 interestFee
    ) external view returns (uint256);
    /// @notice Returns the rate at which interest compounds, in seconds.
    function compoundRate() external view returns (uint256);
    /// @notice Calculates the utilization rate of the market:
    ///         `borrows / (cash + borrows - reserves)`.
    /// @param cash The amount of cash in the market.
    /// @param borrows The amount of borrows in the market.
    /// @param reserves The amount of reserves in the market.
    /// @return The utilization rate between [0, WAD].
    function utilizationRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves
    ) external view returns (uint256);
}