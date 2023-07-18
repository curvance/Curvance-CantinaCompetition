// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

abstract contract ReentrancyGuard {
    uint256 private locked = 1;

    modifier nonReentrant() {
        require(locked == 1, "reentrancyGuard: REENTRANCY");

        locked = 2;

        _;

        locked = 1;
    }
}