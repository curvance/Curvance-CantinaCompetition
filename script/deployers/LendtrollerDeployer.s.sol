// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

import { DeployConfiguration } from "../utils/DeployConfiguration.sol";

contract LendtrollerDeployer is DeployConfiguration {
    address lendtroller;

    function _deployLendtroller(
        address centralRegistry,
        address gaugePool
    ) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");
        require(gaugePool != address(0), "Set the gaugePool!");

        lendtroller = address(
            new Lendtroller(ICentralRegistry(centralRegistry), gaugePool)
        );

        console.log("lendtroller: ", lendtroller);
        _saveDeployedContracts("lendtroller", lendtroller);
    }
}
