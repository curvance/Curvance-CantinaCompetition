// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IAaveToken {
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
}
