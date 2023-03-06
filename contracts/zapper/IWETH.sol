//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IWETH {
    function deposit(uint256 amount) external payable;

    function withdraw(uint256 amount) external;
}
