// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/console.sol";

import { DeployConfiguration } from "../utils/DeployConfiguration.sol";
import { Faucet } from "contracts/testnet/Faucet.sol";

contract DeployFaucet is DeployConfiguration {
    function run(string memory network) external {
        _setConfigurationPath(network);
        _setDeploymentPath(network);
        _deploy();
    }

    function _deploy() internal {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer: ", deployer);

        vm.startBroadcast(deployerPrivateKey);

        address faucet = address(new Faucet(deployer));

        console.log("faucet deployed at: ", faucet);
        _saveDeployedContracts("faucet", faucet);

        vm.stopBroadcast();
    }
}
