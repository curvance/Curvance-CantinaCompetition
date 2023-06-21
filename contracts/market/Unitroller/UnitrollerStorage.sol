// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

contract UnitrollerStorage {
    /**
     * @notice Administrator for this contract
     */
    address public admin;

    /**
     * @notice Pending administrator for this contract
     */
    address public pendingAdmin;

    /**
     * @notice Active brains of Unitroller
     */
    address public lendtrollerImplementation;

    /**
     * @notice Pending brains of Unitroller
     */
    address public pendingLendtrollerImplementation;
}
