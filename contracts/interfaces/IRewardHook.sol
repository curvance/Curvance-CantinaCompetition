// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

interface IRewardHook {
    function onRewardClaim() external;
}
