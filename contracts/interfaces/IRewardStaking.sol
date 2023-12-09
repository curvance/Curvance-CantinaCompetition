// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IRewardStaking {
    function stakeFor(address, uint256) external;

    function stake(uint256) external;

    function withdraw(uint256 amount, bool claim) external;

    function withdrawAndUnwrap(uint256 amount, bool claim) external;

    function earned(address account) external view returns (uint256);

    function getReward() external;

    function getReward(address account, bool claimExtras) external;

    function extraRewardsLength() external view returns (uint256);

    function extraRewards(uint256 pid) external view returns (address);

    function rewardToken() external view returns (address);

    function balanceOf(address account) external view returns (uint256);
}
