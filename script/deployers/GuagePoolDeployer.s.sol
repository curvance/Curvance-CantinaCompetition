// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { GaugePool } from "contracts/gauge/GaugePool.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract GuagePoolDeployer is Script {
    address gaugePool;

    function _deployGaugePool(address centralRegistry) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");

        gaugePool = address(new GaugePool(ICentralRegistry(centralRegistry)));

        console.log("gaugePool: ", gaugePool);
    }
}
