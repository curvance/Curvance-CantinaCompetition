// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { ProtocolMessagingHub } from "contracts/architecture/ProtocolMessagingHub.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { DeployConfiguration } from "../utils/DeployConfiguration.sol";

contract ProtocolMessagingHubDeployer is DeployConfiguration {
    address protocolMessagingHub;

    function deployProtocolMessagingHub(
        address centralRegistry,
        address feeToken,
        address stargateRouter
    ) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");
        require(feeToken != address(0), "Set the feeToken!");
        require(stargateRouter != address(0), "Set the stargateRouter!");

        protocolMessagingHub = address(
            new ProtocolMessagingHub(
                ICentralRegistry(centralRegistry),
                feeToken,
                stargateRouter
            )
        );

        console.log("protocolMessagingHub: ", protocolMessagingHub);
        saveDeployedContracts("protocolMessagingHub", protocolMessagingHub);
    }
}
