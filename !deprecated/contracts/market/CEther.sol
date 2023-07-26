// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CToken, ICentralRegistry } from "contracts/market/collateral/CToken.sol";
import { InterestRateModel } from "contracts/market/interestRates/InterestRateModel.sol";

/// @title Curvance's CEther Contract
/// @notice CToken which wraps Ether
/// @author Curvance
contract CEther is CToken {
    error SenderMismatch();
    error ValueMismatch();

    /// @notice Construct a new CEther money market
    /// @param centralRegistry_ The address of Curvances Central Registry
    /// @param lendtroller_ The address of the Lendtroller
    /// @param interestRateModel_ The address of the interest rate model
    /// @param initialExchangeRateMantissa_ The initial exchange rate, scaled by 1e18
    /// @param name_ ERC-20 name of this token
    /// @param symbol_ ERC-20 symbol of this token
    /// @param decimals_ ERC-20 decimal precision of this token
    constructor(
        ICentralRegistry centralRegistry_,
        address lendtroller_,
        InterestRateModel interestRateModel_,
        uint256 initialExchangeRateMantissa_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    )
        CToken(
            centralRegistry_,
            lendtroller_,
            interestRateModel_,
            initialExchangeRateMantissa_,
            0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
            name_,
            symbol_,
            decimals_
        )
    {}

    /// User Interface

    /// @notice Sender supplies assets into the market and receives cTokens in exchange
    /// @dev Reverts upon any failure
    function mint() external payable {
        mintInternal(msg.value, msg.sender);
    }

    /// @notice Sender supplies assets into the market and receives cTokens in exchange
    /// @dev Reverts upon any failure
    function mintFor(address recipient) external payable {
        mintInternal(msg.value, recipient);
    }

    /// @notice Sender redeems cTokens in exchange for the underlying asset
    /// @dev Accrues interest whether or not the operation succeeds, unless reverted
    /// @param redeemTokens The number of cTokens to redeem into underlying
    function redeem(uint256 redeemTokens) external {
        redeemInternal(redeemTokens);
    }

    /// @notice Sender redeems cTokens in exchange for a specified amount of underlying asset
    /// @dev Accrues interest whether or not the operation succeeds, unless reverted
    /// @param redeemAmount The amount of underlying to redeem
    function redeemUnderlying(uint256 redeemAmount) external {
        redeemUnderlyingInternal(redeemAmount);
    }

    /// @notice Position folding contract will call this function
    /// @param user The user address
    /// @param redeemAmount The amount of the underlying asset to redeem
    function redeemUnderlyingForPositionFolding(
        address user,
        uint256 redeemAmount,
        bytes calldata params
    ) external {
        redeemUnderlyingForPositionFoldingInternal(
            payable(user),
            redeemAmount,
            params
        );
    }

    /// @notice Sender borrows assets from the protocol to their own address
    /// @param borrowAmount The amount of the underlying asset to borrow
    function borrow(uint256 borrowAmount) external {
        borrowInternal(borrowAmount);
    }

    /// @notice Position folding contract will call this function
    /// @param user The user address
    /// @param borrowAmount The amount of the underlying asset to borrow
    function borrowForPositionFolding(
        address user,
        uint256 borrowAmount,
        bytes calldata params
    ) external {
        borrowForPositionFoldingInternal(payable(user), borrowAmount, params);
    }

    /// @notice Sender repays their own borrow
    /// @dev Reverts upon any failure
    function repayBorrow() external payable {
        repayBorrowInternal(msg.value);
    }

    /// @notice Sender repays a borrow belonging to borrower
    /// @dev Reverts upon any failure
    /// @param borrower the account with the debt being payed off
    function repayBorrowBehalf(address borrower) external payable {
        repayBorrowBehalfInternal(borrower, msg.value);
    }

    /// @notice The sender liquidates the borrowers collateral.
    ///  The collateral seized is transferred to the liquidator.
    /// @dev Reverts upon any failure
    /// @param borrower The borrower of this cToken to be liquidated
    /// @param cTokenCollateral The market in which to seize collateral from the borrower
    function liquidateBorrow(
        address borrower,
        CToken cTokenCollateral
    ) external payable {
        liquidateBorrowInternal(borrower, msg.value, cTokenCollateral);
    }

    /// @notice The sender adds to reserves.
    function _addReserves() external payable {
        _addReservesInternal(msg.value);
    }

    /// @notice Send Ether to CEther to mint
    receive() external payable {
        mintInternal(msg.value, msg.sender);
    }

    /// Safe Token

    /// @notice Gets balance of this contract in terms of Ether, before this message
    /// @dev This excludes the value of the current message, if any
    /// @return The quantity of Ether owned by this contract
    function getCashPrior() internal view override returns (uint256) {
        return address(this).balance - msg.value;
    }

    /// @notice Perform the actual transfer in, which is a no-op
    /// @param from Address sending the Ether
    /// @param amount Amount of Ether being sent
    /// @return The actual amount of Ether transferred
    function doTransferIn(
        address from,
        uint256 amount
    ) internal override returns (uint256) {
        // Sanity checks
        if (msg.sender != from) {
            revert SenderMismatch();
        }
        if (msg.value != amount) {
            revert ValueMismatch();
        }
        return amount;
    }

    function doTransferOut(
        address payable to,
        uint256 amount
    ) internal override {
        /// Transfer the Ether, reverts on failure
        /// Had to add NonReentrant to all doTransferOut calls to prevent .call reentry
        (bool success, ) = to.call{ value: amount }("");
        require(success, "CEther: error sending ether");
    }
}
