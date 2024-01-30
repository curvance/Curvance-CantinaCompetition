// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { SwapperLib } from "contracts/libraries/SwapperLib.sol";

interface IExternalCallDataChecker {
    function checkCallData(
        SwapperLib.Swap memory swapData,
        address recipient
    ) external;
}
