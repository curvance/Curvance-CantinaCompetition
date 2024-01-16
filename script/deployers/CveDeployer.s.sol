// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { CVE } from "contracts/token/CVE.sol";
import { CVETestnet } from "contracts/testnet/CVETestnet.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

import { DeployConfiguration } from "../utils/DeployConfiguration.sol";

contract CveDeployer is DeployConfiguration {
    address cve;

    function _deployCVE(address centralRegistry, address team) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");
        require(team != address(0), "Set the builder!");

        cve = address(new CVE(ICentralRegistry(centralRegistry), team));

        console.log("cve: ", cve);
        _saveDeployedContracts("cve", cve);
    }
}
