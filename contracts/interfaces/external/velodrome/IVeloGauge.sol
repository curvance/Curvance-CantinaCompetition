// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IVeloGauge {
    function notifyRewardAmount(address token, uint256 amount) external;

    function getReward(address account, address[] calldata tokens) external;

    function claimFees() external returns (uint256 claimed0, uint256 claimed1);

    function left(address token) external view returns (uint256);

    function isForPair() external view returns (bool);

    function earned(address token, address account)
        external
        view
        returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function deposit(uint256 amount, uint256 tokenId) external;

    function withdraw(uint256 amount) external;
}
