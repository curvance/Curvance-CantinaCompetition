// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface GemLike {
    function approve(address, uint256) external;

    function balanceOf(address) external view returns (uint256);

    function transferFrom(
        address,
        address,
        uint256
    ) external returns (bool);
}