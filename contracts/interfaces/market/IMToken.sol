// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ILendtroller } from "contracts/interfaces/market/ILendtroller.sol";

struct AccountSnapshot {
    address asset;
    bool isCToken;
    uint8 decimals;
    uint256 debtBalance;
    uint256 exchangeRate;
}

interface IMToken {
    function underlying() external view returns (address);

    /// @notice Returns whether the market token is a collateral token
    function isCToken() external view returns (bool);

    /// @notice Get the token balance of the `owner`
    function balanceOf(address owner) external view returns (uint256);

    function seize(
        address liquidator,
        address account,
        uint256 liquidatedTokens,
        uint256 protocolTokens
    ) external;

    function repayWithBadDebt(
        address liquidator, 
        address account, 
        uint256 repayRatio
    ) external;

    function seizeAccountLiquidation(
        address liquidator, 
        address account, 
        uint256 shares
    ) external;

    /// @notice Get a snapshot of the account's balances, and the cached exchange rate
    function getSnapshot(
        address account
    ) external view returns (uint256, uint256, uint256);

    /// @notice Get a snapshot of the account's balances, and the cached exchange rate
    function getSnapshotPacked(
        address account
    ) external view returns (AccountSnapshot memory);

    /// @notice Returns the total amount of MToken
    function totalSupply() external view returns (uint256);

    /// @notice Returns total amount of outstanding borrows of the underlying in this market
    function totalBorrows() external view returns (uint256);

    /// @notice Return the borrow balance of account based on stored data
    function debtBalanceCached(
        address account
    ) external view returns (uint256);

    function lendtroller() external view returns (ILendtroller);

    function exchangeRateCached() external view returns (uint256);

    function startMarket(address initializer) external returns (bool);

    function mint(uint256 mintAmount) external returns (bool);

    function redeem(uint256 tokensToRedeem) external;

    function decimals() external view returns (uint8);
}
