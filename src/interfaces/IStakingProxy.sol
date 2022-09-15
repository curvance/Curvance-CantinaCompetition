// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IStakingProxy {
    function getBalance() external view returns (uint256);

    function withdraw(uint256 amount) external;

    function stake() external;

    function distribute() external;

    function stake(uint256 amount) external;
}
