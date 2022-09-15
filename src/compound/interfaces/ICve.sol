// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface CveInterface {
    function getPriorVotes(address account, uint blockNumber) external view returns (uint96);
}