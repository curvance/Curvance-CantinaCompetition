// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { CurvanceAuxiliaryData } from "contracts/misc/CurvanceAuxiliaryData.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

import { DeployConfiguration } from "../utils/DeployConfiguration.sol";

contract AuxiliaryDataDeployer is DeployConfiguration {
    address auxiliaryData;

    function _deployAuxiliaryData(address centralRegistry) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");

        auxiliaryData = address(
            new CurvanceAuxiliaryData(ICentralRegistry(centralRegistry))
        );

        console.log("auxiliaryData: ", auxiliaryData);
        _saveDeployedContracts("auxiliaryData", auxiliaryData);
    }
}
