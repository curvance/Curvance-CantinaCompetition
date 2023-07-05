// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IPendleMarket {
    function increaseObservationsCardinalityNext(uint16 cardinalityNext)
        external;
}