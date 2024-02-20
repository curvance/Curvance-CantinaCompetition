//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IRewardRouter {
    function stakedGmxTracker() external view returns (address);

    function stakeGmx(uint256 amount) external;

    function unstakeGmx(uint256 amount) external;

    function handleRewards(
        bool shouldClaimGmx,
        bool shouldStakeGmx,
        bool shouldClaimEsGmx,
        bool shouldStakeEsGmx,
        bool shouldStakeMultiplierPoints,
        bool shouldClaimWeth,
        bool shouldConvertWethToEth
    ) external;
}
