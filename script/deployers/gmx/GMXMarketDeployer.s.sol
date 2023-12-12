// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/console.sol";

import { PriceRouter } from "contracts/oracles/PriceRouter.sol";
import { ChainlinkAdaptor } from "contracts/oracles/adaptors/chainlink/ChainlinkAdaptor.sol";
import { GMAdaptor } from "contracts/oracles/adaptors/gmx/GMAdaptor.sol";
import { GMCToken } from "contracts/market/collateral/GMCToken.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";

import { DeployConfiguration } from "../../utils/DeployConfiguration.sol";

contract GMXMarketDeployer is DeployConfiguration {
    function _deployGMXMarket(string memory name, address asset) internal {
        address centralRegistry = _getDeployedContract("centralRegistry");
        console.log("centralRegistry =", centralRegistry);
        require(centralRegistry != address(0), "Set the centralRegistry!");

        address lendtroller = _getDeployedContract("lendtroller");
        console.log("lendtroller =", lendtroller);
        require(lendtroller != address(0), "Set the lendtroller!");

        address priceRouter = _getDeployedContract("priceRouter");
        console.log("priceRouter =", priceRouter);
        require(priceRouter != address(0), "Set the priceRouter!");

        address chainlinkAdaptor = _getDeployedContract("chainlinkAdaptor");
        if (chainlinkAdaptor == address(0)) {
            chainlinkAdaptor = address(
                new ChainlinkAdaptor(ICentralRegistry(centralRegistry))
            );
            console.log("chainlinkAdaptor: ", chainlinkAdaptor);
            _saveDeployedContracts("chainlinkAdaptor", chainlinkAdaptor);
        }
        address gmAdaptor = _getDeployedContract("gmAdaptor");
        if (gmAdaptor == address(0)) {
            gmAdaptor = address(
                new GMAdaptor(
                    ICentralRegistry(centralRegistry),
                    _readConfigAddress(".gmx.reader"),
                    _readConfigAddress(".gmx.dataStore")
                )
            );
            console.log("gmAdaptor: ", gmAdaptor);
            _saveDeployedContracts("gmAdaptor", gmAdaptor);
        }

        // Deploy CToken
        address cToken = _getDeployedContract(name);

        if (cToken == address(0)) {
            cToken = address(
                new GMCToken(
                    ICentralRegistry(centralRegistry),
                    IERC20(asset),
                    lendtroller
                )
            );

            console.log("cToken: ", cToken);
            _saveDeployedContracts(name, cToken);
        }
    }
}
