// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { OneBalanceFeeManager } from "contracts/architecture/OneBalanceFeeManager.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { DeployConfiguration } from "../utils/DeployConfiguration.sol";

contract OneBalanceFeeManagerDeployer is DeployConfiguration {
    address oneBalanceFeeManager;

    function _deployOneBalanceFeeManager(
        address centralRegistry,
        address gelatoOneBalance,
        address polygonOneBalanceFeeManager
    ) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");

        oneBalanceFeeManager = address(
            new OneBalanceFeeManager(
                ICentralRegistry(centralRegistry),
                gelatoOneBalance,
                polygonOneBalanceFeeManager
            )
        );

        console.log("oneBalanceFeeManager: ", oneBalanceFeeManager);
        _saveDeployedContracts("oneBalanceFeeManager", oneBalanceFeeManager);
    }
}
