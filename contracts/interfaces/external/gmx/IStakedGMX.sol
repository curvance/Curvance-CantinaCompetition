//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IStakedGMX {
    function updateRewards() external;

    function stakedAmounts(address) external view returns (uint256);

    function claimable(address) external view returns (uint256);
}
