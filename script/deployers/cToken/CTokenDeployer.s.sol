// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { OracleRouter } from "contracts/oracles/OracleRouter.sol";
import { ChainlinkAdaptor } from "contracts/oracles/adaptors/chainlink/ChainlinkAdaptor.sol";
import { BalancerStablePoolAdaptor } from "contracts/oracles/adaptors/balancer/BalancerStablePoolAdaptor.sol";
import { IVault } from "contracts/oracles/adaptors/balancer/BalancerBaseAdaptor.sol";
import { CTokenPrimitive } from "contracts/market/collateral/CTokenPrimitive.sol";
import { PendlePrincipalTokenAdaptor } from "contracts/oracles/adaptors/pendle/PendlePrincipalTokenAdaptor.sol";
import { IPendlePTOracle } from "contracts/interfaces/external/pendle/IPendlePtOracle.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IPMarket } from "contracts/interfaces/external/pendle/IPMarket.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";

import { DeployConfiguration } from "../../utils/DeployConfiguration.sol";

contract CTokenDeployer is DeployConfiguration {
    struct CTokenParam {
        address asset;
        address chainlinkEth;
        address chainlinkUsd;
    }

    function _deployCToken(
        string memory name,
        CTokenParam memory param
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

        // Setup underlying chainlink adapters.
        if (
            !ChainlinkAdaptor(chainlinkAdaptor).isSupportedAsset(param.asset)
        ) {
            // TO-DO: Have a lookup table here for param assets for whether
            // there are special heartbeats smaller than 24 hours.
            if (param.chainlinkEth != address(0)) {
                ChainlinkAdaptor(chainlinkAdaptor).addAsset(
                    param.asset,
                    param.chainlinkEth,
                    0,
                    false
                );
            }
            // TO-DO: Have a lookup table here for param assets for whether
            // there are special heartbeats smaller than 24 hours.
            if (param.chainlinkUsd != address(0)) {
                ChainlinkAdaptor(chainlinkAdaptor).addAsset(
                    param.asset,
                    param.chainlinkUsd,
                    0,
                    true
                );
            }
            console.log("chainlinkAdaptor.addAsset");
        }

        if (!OracleRouter(oracleRouter).isApprovedAdaptor(chainlinkAdaptor)) {
            OracleRouter(oracleRouter).addApprovedAdaptor(chainlinkAdaptor);
            console.log("oracleRouter.addApprovedAdaptor: ", chainlinkAdaptor);
        }

        try OracleRouter(oracleRouter).assetPriceFeeds(param.asset, 0) returns (
            address feed
        ) {} catch {
            OracleRouter(oracleRouter).addAssetPriceFeed(
                param.asset,
                chainlinkAdaptor
            );
            console.log("oracleRouter.addAssetPriceFeed: ", param.asset);
        }

        // Deploy CToken
        address cToken = _getDeployedContract(name);
        if (cToken == address(0)) {
            cToken = address(
                new CTokenPrimitive(
                    ICentralRegistry(address(centralRegistry)),
                    IERC20(param.asset),
                    marketManager
                )
            );

            console.log("cToken: ", cToken);
            _saveDeployedContracts(name, cToken);

            if (!OracleRouter(oracleRouter).isSupportedAsset(cToken)) {
                OracleRouter(oracleRouter).addMTokenSupport(cToken);
            }
        }

        // followings should be done separate because it requires dust amount deposits
        // marketManager.listToken;
        // marketManager.updateCollateralToken
        // marketManager.setCTokenCollateralCaps
    }
}
