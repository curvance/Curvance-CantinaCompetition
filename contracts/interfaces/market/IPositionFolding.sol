// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IPositionFolding {
    /// @notice Callback function to execute post borrow of
    ///         `borrowToken`'s underlying and swap it to deposit
    ///         new collateral for `borrower`.
    /// @dev Measures slippage after this callback validating that `borrower`
    ///      is still within acceptable liquidity requirements.
    /// @param borrowToken The borrow token borrowed from.
    /// @param borrower The user borrowing that will be swapped into
    ///                 collateral assets deposited into Curvance.
    /// @param borrowAmount The amount of `borrowToken`'s underlying borrowed.
    /// @param params Swap and deposit instructions.
    function onBorrow(
        address borrowToken,
        address borrower,
        uint256 borrowAmount,
        bytes memory params
    ) external;

    /// @notice Callback function to execute post redemption of
    ///         `collateralToken`'s underlying and swap it to repay
    ///         active debt for `redeemer`.
    /// @dev Measures slippage after this callback validating that `redeemer`
    ///      is still within acceptable liquidity requirements.
    /// @param collateralToken The cToken redeemed for its underlying.
    /// @param redeemer The user redeeming collateral that will be used to
    ///                 repay their active debt.
    /// @param collateralAmount The amount of `collateralToken` underlying
    ///                         redeemed.
    /// @param params Swap and repayment instructions.
    function onRedeem(
        address collateralToken,
        address redeemer,
        uint256 collateralAmount,
        bytes memory params
    ) external;
}
