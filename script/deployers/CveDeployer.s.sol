// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { CVE } from "contracts/token/CVE.sol";
import { CVETestnet } from "contracts/testnet/CVETestnet.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { DeployConfiguration } from "../utils/DeployConfiguration.sol";

contract CveDeployer is DeployConfiguration {
    address cve;

    function _deployCve(
        address centralRegistry,
        address tokenBridgeRelayer,
        address team,
        uint256 daoTreasuryAllocation,
        uint256 callOptionAllocation,
        uint256 teamAllocation,
        uint256 initialTokenMint
    ) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");
        require(team != address(0), "Set the team!");

        if (tokenBridgeRelayer == address(0)) {
            cve = address(
                new CVETestnet(
                    ICentralRegistry(centralRegistry),
                    tokenBridgeRelayer,
                    team,
                    daoTreasuryAllocation,
                    callOptionAllocation,
                    teamAllocation,
                    initialTokenMint
                )
            );
        } else {
            cve = address(
                new CVE(
                    ICentralRegistry(centralRegistry),
                    tokenBridgeRelayer,
                    team,
                    daoTreasuryAllocation,
                    callOptionAllocation,
                    teamAllocation,
                    initialTokenMint
                )
            );
        }

        console.log("cve: ", cve);
        _saveDeployedContracts("cve", cve);
    }
}
