// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IVeloGauge {
    function notifyRewardAmount(uint amount) external;

    function getReward(address account) external;

    function stakingToken() external view returns (address);

    function left() external view returns (uint256);

    function isPool() external view returns (bool);

    function earned(address account) external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function deposit(uint256 amount) external;

    function withdraw(uint256 amount) external;

}
