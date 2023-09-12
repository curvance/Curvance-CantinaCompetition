// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IVeloGauge {
    function notifyRewardAmount(address token, uint256 amount) external;

    function getReward(address account, address[] memory tokens) external;

    function stake() external view returns (address);

    function left(address token) external view returns (uint256);

    function isForPair() external view returns (bool);

    function earned(
        address token,
        address account
    ) external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function rewards(uint256 index) external view returns (address);

    function rewardsListLength() external view returns (uint);

    function deposit(uint256 amount, uint256 tokenId) external;

    function withdraw(uint256 amount) external;

    function claimFees() external returns (uint claimed0, uint claimed1);
}
