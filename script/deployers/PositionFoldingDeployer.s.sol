// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { PositionFolding } from "contracts/market/leverage/PositionFolding.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

import { DeployConfiguration } from "../utils/DeployConfiguration.sol";

contract PositionFoldingDeployer is DeployConfiguration {
    address positionFolding;

    function _deployPositionFolding(
        address centralRegistry,
        address lendtroller
    ) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");
        require(lendtroller != address(0), "Set the lendtroller!");

        positionFolding = address(
            new PositionFolding(ICentralRegistry(centralRegistry), lendtroller)
        );

        console.log("positionFolding: ", positionFolding);
        _saveDeployedContracts("positionFolding", positionFolding);
    }
}
