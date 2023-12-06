// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { Zapper } from "contracts/market/zapper/Zapper.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { DeployConfiguration } from "../utils/DeployConfiguration.sol";

contract ZapperDeployer is DeployConfiguration {
    address zapper;

    function deployZapper(
        address centralRegistry,
        address lendtroller,
        address weth
    ) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");
        require(lendtroller != address(0), "Set the lendtroller!");
        require(weth != address(0), "Set the weth!");

        zapper = address(
            new Zapper(ICentralRegistry(centralRegistry), lendtroller, weth)
        );

        console.log("zapper: ", zapper);
        saveDeployedContracts("zapper", zapper);
    }
}
