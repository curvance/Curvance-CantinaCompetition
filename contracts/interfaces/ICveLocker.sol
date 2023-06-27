// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface ICveLocker {
    function getBalance() external view returns (uint256);

    function withdrawFor(address _user, uint256 amount) external;

    function withdrawOnShutdown(uint256 amount) external;

    function stake() external;

    function distribute() external;

    function getRewards(address _user) external view returns (uint256);

    function claimRewards(address _user) external;

    function stake(uint256 amount) external;
}
