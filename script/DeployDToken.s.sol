// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { DeployConfiguration } from "./utils/DeployConfiguration.sol";
import { DTokenDeployer } from "./deployers/dToken/DTokenDeployer.s.sol";

contract DeployDToken is Script, DeployConfiguration, DTokenDeployer {
    using stdJson for string;

    function run(string memory name) external {
        _deploy("ethereum", name);
    }

    function run(string memory network, string memory name) external {
        _deploy(network, name);
    }

    function _deploy(string memory network, string memory name) internal {
        _setConfigurationPath(network);
        _setDeploymentPath(network);

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer: ", deployer);

        string memory configurationJson = vm.readFile(configurationPath);

        vm.startBroadcast(deployerPrivateKey);

        _deployDToken(
            string.concat("D-", name),
            abi.decode(
                configurationJson.parseRaw(
                    string.concat(".markets.dTokens.", name)
                ),
                (DTokenDeployer.DTokenParam)
            )
        );

        vm.stopBroadcast();
    }
}
