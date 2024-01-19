// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/console.sol";

import { OracleRouter } from "contracts/oracles/OracleRouter.sol";
import { ChainlinkAdaptor } from "contracts/oracles/adaptors/chainlink/ChainlinkAdaptor.sol";
import { GMAdaptor } from "contracts/oracles/adaptors/gmx/GMAdaptor.sol";
import { GMCToken } from "contracts/market/collateral/GMCToken.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";

import { DeployConfiguration } from "../../utils/DeployConfiguration.sol";

contract GMXMarketDeployer is DeployConfiguration {
    function _deployGMXMarket(
        string memory name,
        address asset,
        address alteredToken
    ) internal {
        address centralRegistry = _getDeployedContract("centralRegistry");
        console.log("centralRegistry =", centralRegistry);
        require(centralRegistry != address(0), "Set the centralRegistry!");

        address marketManager = _getDeployedContract("marketManager");
        console.log("marketManager =", marketManager);
        require(marketManager != address(0), "Set the marketManager!");

        address oracleRouter = _getDeployedContract("oracleRouter");
        console.log("oracleRouter =", oracleRouter);
        require(oracleRouter != address(0), "Set the oracleRouter!");

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

        if (!OracleRouter(oracleRouter).isApprovedAdaptor(chainlinkAdaptor)) {
            OracleRouter(oracleRouter).addApprovedAdaptor(chainlinkAdaptor);
            console.log("oracleRouter.addApprovedAdaptor: ", chainlinkAdaptor);
        }

        if (!OracleRouter(oracleRouter).isApprovedAdaptor(gmAdaptor)) {
            OracleRouter(oracleRouter).addApprovedAdaptor(gmAdaptor);
            console.log("oracleRouter.addApprovedAdaptor: ", gmAdaptor);
        }

        if (!GMAdaptor(gmAdaptor).isSupportedAsset(asset)) {
            GMAdaptor(gmAdaptor).addAsset(asset, alteredToken);
        }

        try OracleRouter(oracleRouter).assetPriceFeeds(asset, 0) returns (
            address
        ) {} catch {
            OracleRouter(oracleRouter).addAssetPriceFeed(asset, gmAdaptor);
            console.log("oracleRouter.addAssetPriceFeed: ", asset);
        }

        // Deploy CToken
        address cToken = _getDeployedContract(name);

        if (cToken == address(0)) {
            cToken = address(
                new GMCToken(
                    ICentralRegistry(centralRegistry),
                    IERC20(asset),
                    marketManager,
                    _readConfigAddress(".gmx.depositVault"),
                    _readConfigAddress(".gmx.exchangeRouter"),
                    _readConfigAddress(".gmx.router"),
                    _readConfigAddress(".gmx.reader"),
                    _readConfigAddress(".gmx.dataStore"),
                    _readConfigAddress(".gmx.depositHandler")
                )
            );

            console.log("cToken: ", cToken);
            _saveDeployedContracts(name, cToken);
        }
    }
}
