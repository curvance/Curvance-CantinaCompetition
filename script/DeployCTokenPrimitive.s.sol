// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { DeployConfiguration } from "./utils/DeployConfiguration.sol";
import { CTokenDeployer } from "./deployers/cToken/CTokenDeployer.s.sol";

contract DeployCTokenPrimitive is Script, DeployConfiguration, CTokenDeployer {
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

        _deployCToken(
            string.concat("C-", name),
            abi.decode(
                configurationJson.parseRaw(
                    string.concat(".markets.cTokens.", name)
                ),
                (CTokenDeployer.CTokenParam)
            )
        );

        vm.stopBroadcast();
    }
}
