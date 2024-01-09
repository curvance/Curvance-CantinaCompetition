// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { ProtocolMessagingHub } from "contracts/architecture/ProtocolMessagingHub.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

import { DeployConfiguration } from "../utils/DeployConfiguration.sol";

contract ProtocolMessagingHubDeployer is DeployConfiguration {
    address protocolMessagingHub;

    function _deployProtocolMessagingHub(
        address centralRegistry,
        address feeToken,
        address wormholeRelayer,
        address circleRelayer,
        address tokenBridgeRelayer
    ) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");
        require(feeToken != address(0), "Set the feeToken!");
        require(wormholeRelayer != address(0), "Set the wormholeRelayer!");
        require(circleRelayer != address(0), "Set the circleRelayer!");
        require(
            tokenBridgeRelayer != address(0),
            "Set the tokenBridgeRelayer!"
        );

        protocolMessagingHub = address(
            new ProtocolMessagingHub(
                ICentralRegistry(centralRegistry),
                feeToken,
                wormholeRelayer,
                circleRelayer,
                tokenBridgeRelayer
            )
        );

        console.log("protocolMessagingHub: ", protocolMessagingHub);
        _saveDeployedContracts("protocolMessagingHub", protocolMessagingHub);
    }
}
