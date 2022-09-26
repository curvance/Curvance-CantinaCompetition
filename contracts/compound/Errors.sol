// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

abstract contract CommonErros {
    error AddressUnauthorized();
}

abstract contract CTokenErrors is CommonErros {
    ////////// ERRORS //////////
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
    error InvalidUnderlying();
    error TransferFailure();
    error ActionFailure();
}

abstract contract CErc20DelegationErrors is CommonErros {
    error CannotSendValueToFallback();
    error MintFailure();
}
