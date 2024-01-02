// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface VatLike {
    function dai(address) external view returns (uint256);

    function hope(address) external;
}