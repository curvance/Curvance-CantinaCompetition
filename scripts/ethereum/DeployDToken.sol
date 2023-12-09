// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { DeployConfiguration } from "../utils/DeployConfiguration.sol";
import { DTokenDeployer } from "../deployers/dToken/DTokenDeployer.s.sol";

contract DeployDToken is Script, DeployConfiguration, DTokenDeployer {
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

        deployDToken(
            "D-USDC",
            abi.decode(
                configurationJson.parseRaw(".markets.dTokens.USDC"),
                (DTokenDeployer.DTokenParam)
            )
        );
        deployDToken(
            "D-DAI",
            abi.decode(
                configurationJson.parseRaw(".markets.dTokens.DAI"),
                (DTokenDeployer.DTokenParam)
            )
        );
        deployDToken(
            "D-USDT",
            abi.decode(
                configurationJson.parseRaw(".markets.dTokens.USDT"),
                (DTokenDeployer.DTokenParam)
            )
        );

        vm.stopBroadcast();
    }
}
