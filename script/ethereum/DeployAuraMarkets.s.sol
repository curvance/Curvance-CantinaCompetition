// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { DeployConfiguration } from "../utils/DeployConfiguration.sol";
import { AuraMarketDeployer } from "../deployers/aura/AuraMarketDeployer.s.sol";

contract DeployAuraMarkets is Script, DeployConfiguration, AuraMarketDeployer {
    using stdJson for string;

    function run() external {
        _setConfigurationPath("ethereum");
        _setDeploymentPath("ethereum");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer: ", deployer);

        string memory configurationJson = vm.readFile(configurationPath);

        vm.startBroadcast(deployerPrivateKey);

        _deployAuraMarket(
            "C-AURA-RETH-WETH-109",
            abi.decode(
                configurationJson.parseRaw(
                    ".markets.cTokens.AURA-RETH-WETH-109"
                ),
                (AuraMarketDeployer.AuraMarketParam)
            )
        );

        vm.stopBroadcast();
    }
}
