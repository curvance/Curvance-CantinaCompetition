// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./UnitrollerStorage.sol";

/**
 * @title LendtrollerCore
 * @dev Storage for the lendtroller is at this address, while execution is delegated to the `lendtrollerImplementation`.
 * CTokens should reference this contract as their lendtroller.
 */
contract Unitroller is UnitrollerStorage {
    error AddressUnauthorized();

    /**
     * @notice Emitted when pendingLendtrollerImplementation is changed
     */
    event NewPendingImplementation(
        address oldPendingImplementation,
        address newPendingImplementation
    );

    /**
     * @notice Emitted when pendingLendtrollerImplementation is accepted,
     *          which means lendtroller implementation is updated
     */
    event NewImplementation(
        address oldImplementation,
        address newImplementation
    );

    /**
     * @notice Emitted when pendingAdmin is changed
     */
    event NewPendingAdmin(address oldPendingAdmin, address newPendingAdmin);

    /**
     * @notice Emitted when pendingAdmin is accepted, which means admin is updated
     */
    event NewAdmin(address oldAdmin, address newAdmin);

    constructor() {
        // Set admin to caller
        admin = msg.sender;
    }

    /*** Admin Functions ***/
    function _setPendingImplementation(address newPendingImplementation)
        public
    {
        if (msg.sender != admin) {
            revert AddressUnauthorized();
        }

        address oldPendingImplementation = pendingLendtrollerImplementation;

        pendingLendtrollerImplementation = newPendingImplementation;

        emit NewPendingImplementation(
            oldPendingImplementation,
            pendingLendtrollerImplementation
        );
    }

    /**
     * @notice Accepts new implementation of lendtroller. msg.sender must be pendingImplementation
     * @dev Admin function for new implementation to accept it's role as implementation
     */
    function _acceptImplementation() public {
        // Check caller is pendingImplementation and pendingImplementation ≠ address(0)
        if (
            msg.sender != pendingLendtrollerImplementation ||
            pendingLendtrollerImplementation == address(0)
        ) {
            revert AddressUnauthorized();
        }

        // Save current values for inclusion in log
        address oldImplementation = lendtrollerImplementation;
        address oldPendingImplementation = pendingLendtrollerImplementation;

        lendtrollerImplementation = pendingLendtrollerImplementation;

        pendingLendtrollerImplementation = address(0);

        emit NewImplementation(oldImplementation, lendtrollerImplementation);
        emit NewPendingImplementation(
            oldPendingImplementation,
            pendingLendtrollerImplementation
        );
    }

    /**
     * @notice Begins transfer of admin rights. The newPendingAdmin must call `_acceptAdmin` to finalize the transfer.
     * @dev Admin function to begin change of admin.
     *        The newPendingAdmin must call `_acceptAdmin` to finalize the transfer.
     * @param newPendingAdmin New pending admin.
     */
    function _setPendingAdmin(address newPendingAdmin) public {
        // Check caller = admin
        if (msg.sender != admin) {
            revert AddressUnauthorized();
        }

        // Save current value, if any, for inclusion in log
        address oldPendingAdmin = pendingAdmin;

        // Store pendingAdmin with value newPendingAdmin
        pendingAdmin = newPendingAdmin;

        emit NewPendingAdmin(oldPendingAdmin, newPendingAdmin);
    }

    /**
     * @notice Accepts transfer of admin rights. msg.sender must be pendingAdmin
     * @dev Admin function for pending admin to accept role and update admin
     */
    function _acceptAdmin() public {
        // Check caller is pendingAdmin and pendingAdmin ≠ address(0)
        if (msg.sender != pendingAdmin || msg.sender == address(0)) {
            revert AddressUnauthorized();
        }

        // Save current values for inclusion in log
        address oldAdmin = admin;
        address oldPendingAdmin = pendingAdmin;

        // Store admin with value pendingAdmin
        admin = pendingAdmin;

        // Clear the pending value
        pendingAdmin = address(0);

        emit NewAdmin(oldAdmin, admin);
        emit NewPendingAdmin(oldPendingAdmin, pendingAdmin);
    }

    /**
     * @dev Delegates execution to an implementation contract.
     * It returns to the external caller whatever the implementation returns
     * or forwards reverts.
     */
    fallback() external payable {
        // delegate all other functions to current implementation
        (bool success, ) = lendtrollerImplementation.delegatecall(msg.data);

        assembly {
            let free_mem_ptr := mload(0x40)
            returndatacopy(free_mem_ptr, 0, returndatasize())

            switch success
            case 0 {
                revert(free_mem_ptr, returndatasize())
            }
            default {
                return(free_mem_ptr, returndatasize())
            }
        }
    }
}
