// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IRewards {
    function rewardToken() external view returns (address);

    function getReward() external;
}
