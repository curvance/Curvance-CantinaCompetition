// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { PositionFolding } from "contracts/market/utils/PositionFolding.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

import { DeployConfiguration } from "../utils/DeployConfiguration.sol";

contract PositionFoldingDeployer is DeployConfiguration {
    address positionFolding;

    function _deployPositionFolding(
        address centralRegistry,
        address marketManager
    ) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");
        require(marketManager != address(0), "Set the marketManager!");

        positionFolding = address(
            new PositionFolding(ICentralRegistry(centralRegistry), marketManager)
        );

        console.log("positionFolding: ", positionFolding);
        _saveDeployedContracts("positionFolding", positionFolding);
    }
}
