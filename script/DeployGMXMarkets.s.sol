// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { stdJson } from "forge-std/StdJson.sol";
import { console } from "forge-std/console.sol";
import { GMXMarketDeployer } from "./deployers/gmx/GMXMarketDeployer.s.sol";

contract DeployGMXMarkets is GMXMarketDeployer {
    using stdJson for string;

    function run(string memory name) external {
        _deploy("arbitrum", name);
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

        vm.startBroadcast(deployerPrivateKey);

        _deployGMXMarket(
            name,
            _readConfigAddress(string.concat(".gmx.", name))
        );

        vm.stopBroadcast();
    }
}
