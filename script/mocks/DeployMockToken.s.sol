// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/console.sol";

import { MockToken } from "contracts/mocks/MockToken.sol";

import { DeployConfiguration } from "../utils/DeployConfiguration.sol";

contract DeployMockToken is DeployConfiguration {
    function run(
        string memory network,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) external {
        _setConfigurationPath(network);
        _setDeploymentPath(network);

        _deploy(name, symbol, decimals);
    }

    function _deploy(
        string memory name,
        string memory symbol,
        uint8 decimals
    ) internal {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer: ", deployer);

        vm.startBroadcast(deployerPrivateKey);

        address token = address(new MockToken(name, symbol, decimals));

        console.log("token deployed at: ", token);
        _saveDeployedContracts(symbol, token);

        vm.stopBroadcast();
    }
}
