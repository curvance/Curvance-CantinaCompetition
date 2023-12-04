// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { VeCVE } from "contracts/token/VeCVE.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { DeployConfiguration } from "../utils/DeployConfiguration.sol";

contract VeCveDeployer is DeployConfiguration {
    address veCve;

    function deployVeCve(
        address centralRegistry,
        uint256 clPointMultiplier
    ) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");

        veCve = address(
            new VeCVE(ICentralRegistry(centralRegistry), clPointMultiplier)
        );

        console.log("veCve: ", veCve);
        saveDeployedContracts("veCve", veCve);
    }
}
