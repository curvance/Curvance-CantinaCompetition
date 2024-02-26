// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

interface IBlastCentralRegistry is ICentralRegistry {
    function nativeYieldManager() external view returns (address);
}