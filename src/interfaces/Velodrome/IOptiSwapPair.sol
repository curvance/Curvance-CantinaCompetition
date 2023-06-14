// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IOptiSwapPair {
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
}
