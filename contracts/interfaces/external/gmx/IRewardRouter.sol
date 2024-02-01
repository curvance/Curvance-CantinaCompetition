//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IRewardRouter {
    function stakeEsGmx(uint256 amount) external;

    function claimEsGmx() external;
}
