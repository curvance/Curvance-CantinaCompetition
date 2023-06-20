// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IPositionFolding {
    function onBorrow(address cToken, address borrower, uint256 amount, bytes memory params) external;

    function onRedeem(address cToken, address redeemer, uint256 amount, bytes memory params) external;
}
