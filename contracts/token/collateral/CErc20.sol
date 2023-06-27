// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/market/IDelegateToken.sol";
import "../../interfaces/market/IEIP20NonStandard.sol";
import "./CToken.sol";
import "./storage/CErc20Interface.sol";

/**
 * @title Curvance's CErc20 Contract
 * @notice CTokens which wrap an EIP-20 underlying
 * @author Curvance
 */
contract CErc20 is CErc20Interface, CToken {
    using SafeERC20 for IERC20;

    /**
     * @notice Initialize the new money market
     * @param underlying_ The address of the underlying asset
     * @param lendtroller_ The address of the Lendtroller
     * @param gaugePool_ The address of the gauge pool
     * @param interestRateModel_ The address of the interest rate model
     * @param initialExchangeRateScaled_ The initial exchange rate, scaled by 1e18
     * @param name_ ERC-20 name of this token
     * @param symbol_ ERC-20 symbol of this token
     * @param decimals_ ERC-20 decimal precision of this token
     */
    function initialize(
        address underlying_,
        LendtrollerInterface lendtroller_,
        address gaugePool_,
        InterestRateModel interestRateModel_,
        uint256 initialExchangeRateScaled_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) public {
        // CToken initialize does the bulk of the work
        super.initialize(
            lendtroller_,
            gaugePool_,
            interestRateModel_,
            initialExchangeRateScaled_,
            name_,
            symbol_,
            decimals_
        );
        // Set underlying and sanity check it
        underlying = underlying_;
        IEIP20(underlying).totalSupply();
    }

    /*** User Interface ***/

    /**
     * @notice Sender supplies assets into the market and receives cTokens in exchange
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param mintAmount The amount of the underlying asset to supply
     * @return bool true=success
     */
    function mint(uint256 mintAmount) external override returns (bool) {
        mintInternal(mintAmount, msg.sender);
        return true;
    }

    /**
     * @notice Sender supplies assets into the market and receives cTokens in exchange
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param mintAmount The amount of the underlying asset to supply
     * @param recipient The recipient address
     * @return bool true=success
     */
    function mintFor(uint256 mintAmount, address recipient)
        external
        returns (bool)
    {
        mintInternal(mintAmount, recipient);
        return true;
    }

    /**
     * @notice Sender redeems cTokens in exchange for the underlying asset
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param redeemTokens The number of cTokens to redeem into underlying
     */
    function redeem(uint256 redeemTokens) external override {
        redeemInternal(redeemTokens);
    }

    /**
     * @notice Sender redeems cTokens in exchange for a specified amount of underlying asset
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param redeemAmount The amount of underlying to redeem
     */
    function redeemUnderlying(uint256 redeemAmount) external override {
        redeemUnderlyingInternal(redeemAmount);
    }

    /**
     * @notice Position folding contract will call this function
     * @param user The user address
     * @param redeemAmount The amount of the underlying asset to redeem
     */
    function redeemUnderlyingForPositionFolding(
        address user,
        uint256 redeemAmount,
        bytes memory params
    ) external {
        redeemUnderlyingForPositionFoldingInternal(
            payable(user),
            redeemAmount,
            params
        );
    }

    /**
     * @notice Sender borrows assets from the protocol to their own address
     * @param borrowAmount The amount of the underlying asset to borrow
     */
    function borrow(uint256 borrowAmount) external override {
        borrowInternal(borrowAmount);
    }

    /**
     * @notice Position folding contract will call this function
     * @param user The user address
     * @param borrowAmount The amount of the underlying asset to borrow
     */
    function borrowForPositionFolding(
        address user,
        uint256 borrowAmount,
        bytes memory params
    ) external {
        borrowForPositionFoldingInternal(payable(user), borrowAmount, params);
    }

    /**
     * @notice Sender repays their own borrow
     * @param repayAmount The amount to repay, or -1 for the full outstanding amount
     */
    function repayBorrow(uint256 repayAmount) external override {
        repayBorrowInternal(repayAmount);
    }

    /**
     * @notice Sender repays a borrow belonging to borrower
     * @param borrower the account with the debt being payed off
     * @param repayAmount The amount to repay, or -1 for the full outstanding amount
     */
    function repayBorrowBehalf(address borrower, uint256 repayAmount)
        external
        override
    {
        repayBorrowBehalfInternal(borrower, repayAmount);
    }

    /**
     * @notice The sender liquidates the borrowers collateral.
     *  The collateral seized is transferred to the liquidator.
     * @param borrower The borrower of this cToken to be liquidated
     * @param repayAmount The amount of the underlying borrowed asset to repay
     * @param cTokenCollateral The market in which to seize collateral from the borrower
     */
    function liquidateBorrow(
        address borrower,
        uint256 repayAmount,
        CTokenInterface cTokenCollateral
    ) external override {
        liquidateBorrowInternal(borrower, repayAmount, cTokenCollateral);
    }

    /**
     * @notice A public function to sweep accidental ERC-20 transfers to this contract.
     *  Tokens are sent to admin (timelock)
     * @param token The address of the ERC-20 token to sweep
     */
    function sweepToken(IEIP20NonStandard token) external override {
        if (msg.sender != admin) {
            revert AddressUnauthorized();
        }
        if (address(token) == underlying) {
            revert InvalidUnderlying();
        }
        uint256 balance = token.balanceOf(address(this));
        token.transfer(admin, balance);
    }

    /**
     * @notice The sender adds to reserves.
     * @param addAmount The amount fo underlying token to add as reserves
     */
    function _addReserves(uint256 addAmount) external override {
        _addReservesInternal(addAmount);
    }

    /*** Safe Token ***/

    /**
     * @notice Gets balance of this contract in terms of the underlying
     * @dev This excludes the value of the current message, if any
     * @return uint The quantity of underlying tokens owned by this contract
     */
    function getCashPrior() internal view virtual override returns (uint256) {
        IEIP20 token = IEIP20(underlying);
        return token.balanceOf(address(this));
    }

    /**
     * @dev Similar to EIP20 transfer, except it handles a False result from `transferFrom` and reverts in that case.
     *      This will revert due to insufficient balance or insufficient allowance.
     *      This function returns the actual amount received,
     *      which may be less than `amount` if there is a fee attached to the transfer.
     *
     *      Note: This wrapper safely handles non-standard ERC-20 tokens that do not return a value.
     *       See here: https://medium.com/coinmonks/missing-return-value-bug-at-least-130-tokens-affected-d67bf08521ca
     */
    function doTransferIn(address from, uint256 amount)
        internal
        virtual
        override
        returns (uint256)
    {
        // Read from storage once
        address underlying_ = underlying;
        IERC20 token = IERC20(underlying_);
        uint256 balanceBefore = IERC20(underlying_).balanceOf(address(this));
        token.safeTransferFrom(from, address(this), amount);

        bool success;
        assembly {
            switch returndatasize()
            case 0 {
                // This is a non-standard ERC-20
                success := not(0) // set success to true
            }
            case 32 {
                // This is a compliant ERC-20
                returndatacopy(0, 0, 32)
                success := mload(0) // Set `success = returndata` of override external call
            }
            default {
                // This is an excessively non-compliant ERC-20, revert.
                revert(0, 0)
            }
        }

        if (!success) {
            revert TransferFailure();
        }

        // Calculate the amount that was *actually* transferred
        uint256 balanceAfter = IEIP20(underlying_).balanceOf(address(this));
        return balanceAfter - balanceBefore; // underflow already checked above, just subtract
    }

    /**
     * @dev Similar to EIP20 transfer, except it handles a False success from `transfer` and returns an explanatory
     *         error code rather than reverting.
     *      If caller has not called checked protocol's balance,
     *         this may revert due to insufficient cash held in this contract.
     *      If caller has checked protocol's balance prior to this call, and verified
     *      it is >= amount, this should not revert in normal conditions.
     *
     *      Note: This wrapper safely handles non-standard ERC-20 tokens that do not return a value.
     *       See here: https://medium.com/coinmonks/missing-return-value-bug-at-least-130-tokens-affected-d67bf08521ca
     */
    function doTransferOut(address payable to, uint256 amount)
        internal
        virtual
        override
    {
        IEIP20NonStandard token = IEIP20NonStandard(underlying);
        token.transfer(to, amount);

        bool success;
        assembly {
            switch returndatasize()
            case 0 {
                // This is a non-standard ERC-20
                success := not(0) // set success to true
            }
            case 32 {
                // This is a compliant ERC-20
                returndatacopy(0, 0, 32)
                success := mload(0) // Set `success = returndata` of override external call
            }
            default {
                // This is an excessively non-compliant ERC-20, revert.
                revert(0, 0)
            }
        }

        if (!success) {
            revert TransferFailure();
        }
    }

    /**
     * @notice Admin call to delegate the votes of the CVE-like underlying
     * @param cveLikeDelegatee The address to delegate votes to
     * @dev CTokens whose underlying are not CveLike should revert here
     */
    function _delegateCveLikeTo(address cveLikeDelegatee) external {
        if (msg.sender != admin) {
            revert AddressUnauthorized();
        }

        IDelegateToken(underlying).delegate(cveLikeDelegatee);
    }
}
