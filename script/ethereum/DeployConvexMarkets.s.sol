// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { DeployConfiguration } from "../utils/DeployConfiguration.sol";
import { ConvexMarketDeployer } from "../deployers/convex/ConvexMarketDeployer.s.sol";

contract DeployConvexMarkets is
    Script,
    DeployConfiguration,
    ConvexMarketDeployer
{
    using stdJson for string;

    function run() external {
        _setConfigurationPath("ethereum");
        _setDeploymentPath("ethereum");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer: ", deployer);

        string memory configurationJson = vm.readFile(configurationPath);

        vm.startBroadcast(deployerPrivateKey);

        _deployConvexMarket(
            "C-CONVEX-STETH-ETH-177",
            abi.decode(
                configurationJson.parseRaw(
                    ".markets.cTokens.CONVEX-STETH-ETH-177"
                ),
                (ConvexMarketDeployer.ConvexMarketParam)
            )
        );

        vm.stopBroadcast();
    }
}
