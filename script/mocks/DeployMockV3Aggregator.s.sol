// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/console.sol";

import { MockV3Aggregator } from "contracts/mocks/MockV3Aggregator.sol";

import { DeployConfiguration } from "../utils/DeployConfiguration.sol";

contract DeployMockV3Aggregator is DeployConfiguration {
    function run(
        string memory network,
        string memory name,
        uint8 decimals,
        int256 initialAnswer,
        int192 maxAnswer,
        int192 minAnswer
    ) external {
        _setConfigurationPath(network);
        _setDeploymentPath(network);

        _deploy(name, decimals, initialAnswer, maxAnswer, minAnswer);
    }

    function _deploy(
        string memory name,
        uint8 decimals,
        int256 initialAnswer,
        int192 maxAnswer,
        int192 minAnswer
    ) internal {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer: ", deployer);

        vm.startBroadcast(deployerPrivateKey);

        address token = address(
            new MockV3Aggregator(decimals, initialAnswer, maxAnswer, minAnswer)
        );

        console.log("token aggregator deployed at: ", token);
        _saveDeployedContracts(name, token);

        vm.stopBroadcast();
    }
}
