// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { OracleRouter } from "contracts/oracles/OracleRouter.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

import { DeployConfiguration } from "../utils/DeployConfiguration.sol";

contract OracleRouterDeployer is DeployConfiguration {
    address oracleRouter;

    function _deployOracleRouter(
        address centralRegistry,
        address ethUsdFeed
    ) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");
        require(ethUsdFeed != address(0), "Set the ethUsdFeed!");

        oracleRouter = address(
            new OracleRouter(ICentralRegistry(centralRegistry), ethUsdFeed)
        );

        console.log("oracleRouter: ", oracleRouter);
        _saveDeployedContracts("oracleRouter", oracleRouter);
    }
}
