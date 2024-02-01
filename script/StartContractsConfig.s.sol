// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { CVELocker } from "contracts/architecture/CVELocker.sol";
import { CentralRegistry } from "contracts/architecture/CentralRegistry.sol";

import { DeployConfiguration } from "./utils/DeployConfiguration.sol";

contract StartContractsConfig is Script, DeployConfiguration {
    using stdJson for string;

    function run(string memory name) external {
        _update("ethereum", name);
    }

    function run(string memory network, string memory name) external {
        _update(network, name);
    }

    function _update(string memory network, string memory name) internal {
        _setConfigurationPath(network);
        _setDeploymentPath(network);

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer: ", deployer);

        vm.startBroadcast(deployerPrivateKey);

        _startLocker();

        vm.stopBroadcast();
    }

    function _startLocker() internal {
        address centralRegistry = _getDeployedContract("centralRegistry");
        console.log("centralRegistry =", centralRegistry);
        address payable cveLocker = payable(_getDeployedContract("cveLocker"));
        console.log("cveLocker =", cveLocker);
        
        require(centralRegistry != address(0), "Set the centralRegistry!");
        require(CVELocker(cveLocker).lockerStarted() != 2, "Locker already started!");
        require(CentralRegistry(centralRegistry).veCVE() != address(0), "Set veCVE!");

        CVELocker(cveLocker).startLocker();
        console.log("startLocker");
    }
}
