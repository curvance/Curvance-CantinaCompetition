// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IMarketManager } from "contracts/interfaces/market/IMarketManager.sol";

struct AccountSnapshot {
    address asset;
    bool isCToken;
    uint8 decimals;
    uint256 debtBalance;
    uint256 exchangeRate;
}

interface IMToken {
    /// @notice Starts a market by depositing underlying tokens and giving
    ///         ownership to the market itself, this is used on market
    ///         listing by `initializer`. 
    function startMarket(address initializer) external returns (bool);

    /// @notice Returns the underlying token for the market token.
    function underlying() external view returns (address);

    /// @notice Returns the corresponding decimals for a mToken.
    function decimals() external view returns (uint8);

    /// @notice Returns whether the market token is a collateral token.
    function isCToken() external view returns (bool);

    /// @notice Accrues any pending interest inside the market token.
    function accrueInterest() external;

    /// @notice Returns the current token balance of `user`.
    function balanceOf(address user) external view returns (uint256);

    /// @notice Used for minting mTokens by depositing underlying tokens.
    function mint(uint256 amount) external returns (bool);

    /// @notice Used for redeeming underlying tokens by burning mTokens.
    function redeem(uint256 amount) external;

    /// @notice Seizes collateral tokens from `account` based on repaying some
    ///         of their owed dTokens.
    function seize(
        address liquidator,
        address account,
        uint256 liquidatedTokens,
        uint256 protocolTokens
    ) external;

    /// @notice Repays `account`'s debt with also realizing outstanding
    ///         bad debt created by `account`.
    function repayWithBadDebt(
        address liquidator, 
        address account, 
        uint256 repayRatio
    ) external;

    /// @notice Seizes `account`'s collateral token shares due to a
    ///         system wide liquidation.
    function seizeAccountLiquidation(
        address liquidator, 
        address account, 
        uint256 shares
    ) external;

    /// @notice Withdraws all reserves from the gauge and transfers to
    ///         Curvance DAO.
    /// @dev If daoAddress is going to be moved all reserves should be
    ///      withdrawn first, updates interest before executing the reserve
    ///      withdrawal.
    function processWithdrawReserves() external;

    /// @notice Get a snapshot of the account's balances, 
    ///         and the cached exchange rate.
    function getSnapshot(
        address account
    ) external view returns (uint256, uint256, uint256);

    /// @notice Get a snapshot of the account's balances, 
    ///         and the cached exchange rate.
    function getSnapshotPacked(
        address account
    ) external view returns (AccountSnapshot memory);

    /// @notice Returns the total amount of an mToken.
    function totalSupply() external view returns (uint256);

    /// @notice Returns total amount of outstanding borrows of the
    ///         underlying in this dToken market.
    function totalBorrows() external view returns (uint256);

    /// @notice Return the borrow balance of account based on stored data.
    function debtBalanceCached(
        address account
    ) external view returns (uint256);

    /// @notice Calculates the current dToken utilization rate.
    /// @return The utilization rate, in `WAD`.
    function utilizationRate() external view returns (uint256);

    /// @notice Returns the current dToken borrow interest rate per year.
    /// @return The borrow interest rate per year, in `WAD`.
    function borrowRatePerYear() external view returns (uint256);

    /// @notice Returns the current dToken supply interest rate per year.
    /// @return The supply interest rate per year, in `WAD`.
    function supplyRatePerYear() external view returns (uint256);

    /// @notice Returns the Market Manager associated with the mToken.
    function marketManager() external view returns (IMarketManager);

    /// @notice Returns the current Exchange Rate for the mToken to its
    ///         underlying token, without accruing pending interest.
    function exchangeRateCached() external view returns (uint256);
}
