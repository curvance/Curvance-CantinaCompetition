// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "contracts/market/interestRates/InterestRateModel.sol";
import { ILendtroller } from "contracts/interfaces/market/ILendtroller.sol";

interface ICToken {
    ////////// ERRORS //////////

    error AddressUnauthorized();
    error FailedNotFromPositionFolding();
    error FailedFreshnessCheck();
    error CannotEqualZero();
    error ExcessiveValue();
    error TransferNotAllowed();
    error PreviouslyInitialized();
    error RedeemTransferOutNotPossible();
    error BorrowCashNotAvailable();
    error SelfLiquidationNotAllowed();
    error LendtrollerMismatch();
    error ValidationFailed();
    error ReduceReservesCashNotAvailable();
    error ReduceReservesCashValidation();

    ////////// MARKET EVENTS //////////

    /// @notice Event emitted when interest is accrued
    event AccrueInterest(
        uint256 cashPrior,
        uint256 interestAccumulated,
        uint256 borrowIndex,
        uint256 totalBorrows
    );

    /// @notice Event emitted when tokens are minted
    event Mint(
        address user,
        uint256 mintAmount,
        uint256 mintTokens,
        address minter
    );

    /// @notice Event emitted when tokens are redeemed
    event Redeem(address redeemer, uint256 redeemAmount, uint256 redeemTokens);

    /// @notice Event emitted when underlying is borrowed
    event Borrow(
        address borrower,
        uint256 borrowAmount,
        uint256 accountBorrows,
        uint256 totalBorrows
    );

    /// @notice Event emitted when a borrow is repaid
    event RepayBorrow(
        address payer,
        address borrower,
        uint256 repayAmount,
        uint256 accountBorrows,
        uint256 totalBorrows
    );

    /// @notice Event emitted when a borrow is liquidated
    event LiquidateBorrow(
        address liquidator,
        address borrower,
        uint256 repayAmount,
        address cTokenCollateral,
        uint256 seizeTokens
    );

    ////////// ADMIN EVENTS //////////

    /// @notice Event emitted when lendtroller is changed
    event NewLendtroller(
        ILendtroller oldLendtroller,
        ILendtroller newLendtroller
    );

    /// @notice Event emitted when interestRateModel is changed
    event NewMarketInterestRateModel(
        InterestRateModel oldInterestRateModel,
        InterestRateModel newInterestRateModel
    );

    /// @notice Event emitted when the reserve factor is changed
    event NewReserveFactor(
        uint256 oldReserveFactorScaled,
        uint256 newReserveFactorScaled
    );

    /// @notice Event emitted when the reserves are added
    event ReservesAdded(
        address benefactor,
        uint256 addAmount,
        uint256 newTotalReserves
    );

    /// @notice Event emitted when the reserves are reduced
    event ReservesReduced(
        address admin,
        uint256 reduceAmount,
        uint256 newTotalReserves
    );

    /// @notice EIP20 Transfer event
    event Transfer(address indexed from, address indexed to, uint256 amount);

    /// @notice EIP20 Approval event
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 amount
    );

    function isCToken() external view returns (bool);

    function underlying() external view returns (address);

    function symbol() external view returns (string memory);

    function totalBorrows() external view returns (uint256);

    function lendtroller() external view returns (ILendtroller);

    function transfer(address dst, uint256 amount) external returns (bool);

    function transferFrom(
        address src,
        address dst,
        uint256 amount
    ) external returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function balanceOfUnderlying(address owner) external returns (uint256);

    function getAccountSnapshot(
        address account
    ) external view returns (uint256, uint256, uint256);

    function borrowRatePerBlock() external view returns (uint256);

    function supplyRatePerBlock() external view returns (uint256);

    function totalBorrowsCurrent() external returns (uint256);

    function borrowBalanceCurrent(address account) external returns (uint256);

    function borrowBalanceStored(
        address account
    ) external view returns (uint256);

    function exchangeRateCurrent() external returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function getCash() external view returns (uint256);

    function accrueInterest() external;

    function seize(
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) external;

    /// Admin Functions

    function _setLendtroller(ILendtroller newLendtroller) external;

    function _setReserveFactor(uint256 newReserveFactorMantissa) external;

    function _reduceReserves(uint256 reduceAmount) external;

    function _setInterestRateModel(
        InterestRateModel newInterestRateModel
    ) external;

    function accrualBlockTimestamp() external view returns (uint256);
}
