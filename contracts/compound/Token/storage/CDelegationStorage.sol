// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./CommonError.sol";

abstract contract CDelegationStorage is CommonError{
    error CannotSendValueToFallback();
    error MintFailure();

    /**
     * @notice Implementation address for this contract
     */
    address public implementation;

    /**
     * @notice Emitted when implementation is changed
     */
    event NewImplementation(address oldImplementation, address newImplementation);
}
