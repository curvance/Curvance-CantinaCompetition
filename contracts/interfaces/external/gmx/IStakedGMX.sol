//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IStakedGMX {
    function isHandler(address) external view returns (bool);

    function rewardToken() external view returns (address);
}
