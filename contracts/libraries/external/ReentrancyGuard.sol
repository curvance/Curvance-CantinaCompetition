// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

abstract contract ReentrancyGuard {

    /// STORAGE ///
    uint256 private LOCKED = 1;

    /// ERRORS ///

    error ReentrancyGuard__Reentrancy();

    /// MODIFIERS ///

    modifier nonReentrant() {
        if (LOCKED != 1){
            assembly {
                // `bytes4(keccak256(bytes("ReentrancyGuard__Reentrancy()")))`
                mstore(0x00, 0xa8d4d15b)
                // return bytes 29-32 for the selector
                revert(0x1c, 0x04)
            }
        }

        LOCKED = 2;

        _;

        LOCKED = 1;
    }
}