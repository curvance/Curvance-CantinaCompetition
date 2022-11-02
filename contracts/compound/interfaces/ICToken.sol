// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./IComptroller.sol";
import "../InterestRateModel/InterestRateModel.sol";
import "./IEip20NonStandard.sol";

import "../Storage.sol";


abstract contract CTokenInterface is CTokenStorage {
    
    ////////// MARKET EVENTS //////////
    /**
     * @notice Event emitted when interest is accrued
     */
    event AccrueInterest(uint cashPrior, uint interestAccumulated, uint borrowIndex, uint totalBorrows);

    /**
     * @notice Event emitted when tokens are minted
     */
    event Mint(address minter, uint mintAmount, uint mintTokens);

    /**
     * @notice Event emitted when tokens are redeemed
     */
    event Redeem(address redeemer, uint redeemAmount, uint redeemTokens);

    /**
     * @notice Event emitted when underlying is borrowed
     */
    event Borrow(address borrower, uint borrowAmount, uint accountBorrows, uint totalBorrows);

    /**
     * @notice Event emitted when a borrow is repaid
     */
    event RepayBorrow(address payer, address borrower, uint repayAmount, uint accountBorrows, uint totalBorrows);

    /**
     * @notice Event emitted when a borrow is liquidated
     */
    event LiquidateBorrow(address liquidator, address borrower, uint repayAmount, address cTokenCollateral, uint seizeTokens);


    ////////// ADMIN EVENTS //////////
    /**
     * @notice Event emitted when pendingAdmin is changed
     */
    event NewPendingAdmin(address oldPendingAdmin, address newPendingAdmin);

    /**
     * @notice Event emitted when pendingAdmin is accepted, which means admin is updated
     */
    event NewAdmin(address oldAdmin, address newAdmin);

    /**
     * @notice Event emitted when comptroller is changed
     */
    event NewComptroller(ComptrollerInterface oldComptroller, ComptrollerInterface newComptroller);

    /**
     * @notice Event emitted when interestRateModel is changed
     */
    event NewMarketInterestRateModel(InterestRateModel oldInterestRateModel, InterestRateModel newInterestRateModel);

    /**
     * @notice Event emitted when the reserve factor is changed
     */
    event NewReserveFactor(uint oldReserveFactorScaled, uint newReserveFactorScaled);

    /**
     * @notice Event emitted when the reserves are added
     */
    event ReservesAdded(address benefactor, uint addAmount, uint newTotalReserves);

    /**
     * @notice Event emitted when the reserves are reduced
     */
    event ReservesReduced(address admin, uint reduceAmount, uint newTotalReserves);

    /**
     * @notice EIP20 Transfer event
     */
    event Transfer(address indexed from, address indexed to, uint amount);

    /**
     * @notice EIP20 Approval event
     */
    event Approval(address indexed owner, address indexed spender, uint amount);

    /*** User Interface ***/
    function transfer(address dst, uint amount) virtual external returns (bool);
    function transferFrom(address src, address dst, uint amount) virtual external returns (bool);
    function approve(address spender, uint amount) virtual external returns (bool);
    function allowance(address owner, address spender) virtual external view returns (uint);
    function balanceOf(address owner) virtual external view returns (uint);
    function balanceOfUnderlying(address owner) virtual external returns (uint);
    function getAccountSnapshot(address account) virtual external view returns (uint, uint, uint);
    function borrowRatePerBlock() virtual external view returns (uint);
    function supplyRatePerBlock() virtual external view returns (uint);
    function totalBorrowsCurrent() virtual external returns (uint);
    function borrowBalanceCurrent(address account) virtual external returns (uint);
    function borrowBalanceStored(address account) virtual external view returns (uint);
    function exchangeRateCurrent() virtual public returns (uint);
    function exchangeRateStored() virtual public view returns (uint);
    function getCash() virtual external view returns (uint);
    function accrueInterest() virtual public;
    function seize(address liquidator, address borrower, uint seizeTokens) virtual external;

    /*** Admin Functions ***/
    function _setPendingAdmin(address payable newPendingAdmin) virtual external;
    function _acceptAdmin() virtual external;
    function _setComptroller(ComptrollerInterface newComptroller) virtual public;
    function _setReserveFactor(uint newReserveFactorMantissa) virtual external;
    function _reduceReserves(uint reduceAmount) virtual external;
    function _setInterestRateModel(InterestRateModel newInterestRateModel) virtual external;
    
    /*** Getter Functions ***/
    // function getIsCToken() virtual external view returns (bool);
}

// contract CErc20Storage {
//     /**
//      * @notice Underlying asset for this CToken
//      */
//     address public underlying;
// }

abstract contract CErc20Interface is CErc20Storage {

    /*** User Interface ***/
    function mint(uint mintAmount) virtual external returns (bool);
    function redeem(uint redeemTokens) virtual external; // returns (bool);
    function redeemUnderlying(uint redeemAmount) virtual external; // returns (bool);
    function borrow(uint borrowAmount) virtual external;
    function repayBorrow(uint repayAmount) virtual external;
    function repayBorrowBehalf(address borrower, uint repayAmount) virtual external;
    function liquidateBorrow(address borrower, uint repayAmount, CTokenInterface cTokenCollateral) virtual external;
    function sweepToken(EIP20NonStandardInterface token) virtual external;

    /*** Admin Functions ***/
    function _addReserves(uint addAmount) virtual external;  
}


abstract contract CDelegatorInterface is CDelegationStorage {
    /**
     * @notice Called by the admin to update the implementation of the delegator
     * @param implementation_ The address of the new implementation for delegation
     * @param allowResign Flag to indicate whether to call _resignImplementation on the old implementation
     * @param becomeImplementationData The encoded bytes data to be passed to _becomeImplementation
     */
    function _setImplementation(
        address implementation_, 
        bool allowResign, 
        bytes memory becomeImplementationData
    ) virtual external;
}

abstract contract CDelegateInterface is CDelegationStorage {
    /**
     * @notice Called by the delegator on a delegate to initialize it for duty
     * @dev Should revert if any issues arise which make it unfit for delegation
     * @param data The encoded bytes data for any initialization
     */
    function _becomeImplementation(bytes memory data) virtual external;

    /**
     * @notice Called by the delegator on a delegate to forfeit its responsibility
     */
    function _resignImplementation() virtual external;
}
