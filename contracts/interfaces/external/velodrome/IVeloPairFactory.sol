// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IVeloPairFactory {
    function allPoolsLength() external view returns (uint);

    function isPair(address pair) external view returns (bool);

    function getPair(
        address tokenA,
        address tokenB,
        bool stable
    ) external view returns (address);

    function createPair(
        address tokenA,
        address tokenB,
        bool stable
    ) external returns (address pair);

    function getFee(bool _stable) external view returns (uint);
}
