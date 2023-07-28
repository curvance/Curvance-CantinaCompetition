// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IMToken {

    /// @notice Returns whether the market token is collateral or debt 1 = collateral, 0 = debt
    function tokenType() external view returns (uint256);

    /// @notice Returns whether the market token is debt or not 1 = true, 0 = false
    function isDToken() external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function seize(
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) external;

    /// @notice Get a snapshot of the account's balances, and the cached exchange rate
    function getAccountSnapshot(address account) external view returns (uint256, uint256, uint256);

}
