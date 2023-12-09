// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { PriceRouter } from "contracts/oracles/PriceRouter.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { DeployConfiguration } from "../utils/DeployConfiguration.sol";

contract PriceRouterDeployer is DeployConfiguration {
    address priceRouter;

    function deployPriceRouter(
        address centralRegistry,
        address ethUsdFeed
    ) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");
        require(ethUsdFeed != address(0), "Set the ethUsdFeed!");

        priceRouter = address(
            new PriceRouter(ICentralRegistry(centralRegistry), ethUsdFeed)
        );

        console.log("priceRouter: ", priceRouter);
        _saveDeployedContracts("priceRouter", priceRouter);
    }
}
