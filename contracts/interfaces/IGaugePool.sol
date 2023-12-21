// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IGaugePool {
    /// @notice Updates Gauge Emissions for a particular pool
    function setEmissionRates(
        uint256 epoch,
        address[] memory tokens,
        uint256[] memory poolWeights
    ) external;

    /// @notice Deposit into gauge pool
    /// @param token Pool token address
    /// @param user User address
    /// @param amount Amounts to deposit
    function deposit(
        address token,
        address user,
        uint256 amount
    ) external;

    /// @notice Withdraw from gauge pool
    /// @param token Pool token address
    /// @param user The user address
    /// @param amount Amounts to withdraw
    function withdraw(
        address token,
        address user,
        uint256 amount
    ) external;
}
