// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ILendtroller } from "contracts/interfaces/market/ILendtroller.sol";

interface IMToken {

    /// @notice Returns whether the market token is collateral or debt 1 = collateral, 0 = debt
    function tokenType() external view returns (uint256);

    /// @notice Get the token balance of the `owner`
    function balanceOf(address owner) external view returns (uint256);

    function seize(
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) external;

    /// @notice Get a snapshot of the account's balances, and the cached exchange rate
    function getAccountSnapshot(address account) external view returns (uint256, uint256, uint256);

    /// @notice Total amount of outstanding borrows of the underlying in this market
    function totalBorrows() external view returns (uint256);

    /// @notice Return the borrow balance of account based on stored data
    function borrowBalanceStored(
        address account
    ) external view returns (uint256);

    function lendtroller() external view returns (ILendtroller);

    function exchangeRateStored() external view returns (uint256);
    
    function getBorrowTimestamp(address account) external view returns (uint256);

}
