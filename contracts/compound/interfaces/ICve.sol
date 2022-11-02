// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface CveInterface {
    function getPastVotes(address account, uint256 blockNumber) external view returns (uint256);
}
