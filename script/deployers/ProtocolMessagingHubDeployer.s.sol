// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { ProtocolMessagingHub } from "contracts/architecture/ProtocolMessagingHub.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract ProtocolMessagingHubDeployer is Script {
    address protocolMessagingHub;

    function deployProtocolMessagingHub(
        address centralRegistry,
        address feeToken,
        address wormholeRelayer,
        address circleRelayer
    ) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");
        require(feeToken != address(0), "Set the feeToken!");
        require(wormholeRelayer != address(0), "Set the wormholeRelayer!");
        require(circleRelayer != address(0), "Set the circleRelayer!");

        protocolMessagingHub = address(
            new ProtocolMessagingHub(
                ICentralRegistry(centralRegistry),
                feeToken,
                wormholeRelayer,
                circleRelayer
            )
        );

        console.log("protocolMessagingHub: ", protocolMessagingHub);
    }
}
