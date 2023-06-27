// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

interface IGaugePool {
    // @notice Updates Gauge Rewards for a particular pool
    function setRewardPerSecOfNextEpoch(uint256 epoch, uint256 rewardPerSec) external;
    // @notice Updates Gauge Emissions for a particular pool
    function setEmissionRates(uint256 epoch, address[] memory tokens, uint256[] memory poolWeights) external;
}
