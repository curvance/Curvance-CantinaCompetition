// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IPositionFolding {
    function onBorrow(address cToken, address borrower, uint256 amount, bytes memory params) external;
}
