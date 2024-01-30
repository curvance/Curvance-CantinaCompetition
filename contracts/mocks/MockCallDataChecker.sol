// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IAggregationRouterV5 } from "contracts/interfaces/external/1inch/IAggregationRouterV5.sol";
import { UniswapV3Pool } from "contracts/interfaces/external/uniswap/UniswapV3Pool.sol";
import { CallDataCheckerBase, SwapperLib } from "contracts/market/checker/CallDataCheckerBase.sol";

contract MockCallDataChecker is CallDataCheckerBase {
    constructor(address _target) CallDataCheckerBase(_target) {}

    function checkCallData(
        SwapperLib.Swap memory _swapData,
        address _recipient
    ) external view override {}
}
