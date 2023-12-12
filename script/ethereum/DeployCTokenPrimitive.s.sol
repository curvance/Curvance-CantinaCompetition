// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { DeployConfiguration } from "../utils/DeployConfiguration.sol";
import { PendlePTDeployer } from "../deployers/cToken/PendlePTDeployer.s.sol";

contract DeployCTokenPrimitive is
    Script,
    DeployConfiguration,
    PendlePTDeployer
{
    using stdJson for string;

    function setConfigurationPath() internal {
        string memory root = vm.projectRoot();
        configurationPath = string.concat(root, "/config/ethereum.json");
    }

    function setDeploymentPath() internal {
        string memory root = vm.projectRoot();
        deploymentPath = string.concat(root, "/deployments/ethereum.json");
    }

    function run() external {
        setConfigurationPath();
        setDeploymentPath();

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer: ", deployer);

        string memory configurationJson = vm.readFile(configurationPath);

        vm.startBroadcast(deployerPrivateKey);

        _deployPendlePT(
            "C-PendlePT-stETH-26DEC24",
            abi.decode(
                configurationJson.parseRaw(
                    ".markets.cTokens.PendlePT-stETH-26DEC24"
                ),
                (PendlePTDeployer.PendlePTParam)
            )
        );

        vm.stopBroadcast();
    }
}
