// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;


abstract contract CTokenErrors {
        
    ////////// ERRORS //////////
    error AddressUnauthorized();
    error FailedFreshnessCheck();
    error CannotEqualZero();
    error ExcessiveValue();
    error TransferNotAllowed();
    error PreviouslyInitialized();
    error RedeemTransferOutNotPossible();
    error BorrowCashNotAvailable();
    error SelfLiquidiationNotAllowed();
    error ComptrollerMismatch();
    error ValidationFailed();
    /// TODO SEARCH FOR THESE FOR POTENTIAL CHANGES
    error ReduceReservesCashNotAvailable();
    error ReduceReservesCashValidation();


}

abstract contract CErc20Errors {


    error AddressUnauthorized();
    error InvalidUnderlying();
    error TransferFailure();
    error ActionFailure();

}

abstract contract CErc20DelegationErrors {

    error AddressUnauthorized();
    error CannotSendValueToFallback();
    error MintFailure();
}