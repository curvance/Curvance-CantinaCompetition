//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IStakedGMX {
    function stakedAmounts(address) external view returns (uint256);
}
