// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

abstract contract CErc20Storage {
    error InvalidUnderlying();
    error TransferFailure();
    error ActionFailure();

    /**
     * @notice Underlying asset for this CToken
     */
    address public underlying;
}
