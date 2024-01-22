// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { Zapper } from "contracts/market/zapper/Zapper.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

import { DeployConfiguration } from "../utils/DeployConfiguration.sol";

contract ZapperDeployer is DeployConfiguration {
    address zapper;

    function _deployZapper(
        address centralRegistry,
        address marketManager,
        address weth
    ) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");
        require(marketManager != address(0), "Set the marketManager!");
        require(weth != address(0), "Set the weth!");

        zapper = address(
            new Zapper(ICentralRegistry(centralRegistry), marketManager, weth)
        );

        console.log("zapper: ", zapper);
        _saveDeployedContracts("zapper", zapper);
    }
}
