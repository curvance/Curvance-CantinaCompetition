// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ICToken {
    function vault() external view returns (address);
}
