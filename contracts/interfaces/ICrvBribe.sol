// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

interface ICrvBribe {
    function rewards_per_gauge(address gauge) external view returns (address[] memory);

    function gauges_per_reward(address reward) external view returns (address[] memory);

    function add_reward_amount(
        address gauge,
        address reward_token,
        uint256 amount
    ) external returns (bool);

    function claimable(
        address user,
        address gauge,
        address reward_token
    ) external view returns (uint256);

    function claim_reward(
        address user,
        address gauge,
        address reward_token
    ) external returns (uint256);
}
