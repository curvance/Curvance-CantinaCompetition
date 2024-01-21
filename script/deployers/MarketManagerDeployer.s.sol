// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { MarketManager } from "contracts/market/MarketManager.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

import { DeployConfiguration } from "../utils/DeployConfiguration.sol";

contract MarketManagerDeployer is DeployConfiguration {
    address marketManager;

    function _deployMarketManager(
        address centralRegistry,
        address gaugePool
    ) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");
        require(gaugePool != address(0), "Set the gaugePool!");

        marketManager = address(
            new MarketManager(ICentralRegistry(centralRegistry), gaugePool)
        );

        console.log("marketManager: ", marketManager);
        _saveDeployedContracts("marketManager", marketManager);
    }
}
