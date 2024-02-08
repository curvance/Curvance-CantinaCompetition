// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { ComplexZapper } from "contracts/market/utils/ComplexZapper.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

import { DeployConfiguration } from "../utils/DeployConfiguration.sol";

contract ComplexZapperDeployer is DeployConfiguration {
    address complexZapper;

    function _deployComplexZapper(
        address centralRegistry,
        address marketManager,
        address weth
    ) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");
        require(marketManager != address(0), "Set the marketManager!");
        require(weth != address(0), "Set the weth!");

        complexZapper = address(
            new ComplexZapper(ICentralRegistry(centralRegistry), marketManager, weth)
        );

        console.log("complexZapper: ", complexZapper);
        _saveDeployedContracts("complexZapper", complexZapper);
    }
}
