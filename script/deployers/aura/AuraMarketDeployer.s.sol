// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { AuraCToken } from "contracts/market/collateral/AuraCToken.sol";
import { OracleRouter } from "contracts/oracles/OracleRouter.sol";
import { ChainlinkAdaptor } from "contracts/oracles/adaptors/chainlink/ChainlinkAdaptor.sol";
import { BalancerStablePoolAdaptor } from "contracts/oracles/adaptors/balancer/BalancerStablePoolAdaptor.sol";
import { IVault } from "contracts/oracles/adaptors/balancer/BalancerBaseAdaptor.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";

import { DeployConfiguration } from "../../utils/DeployConfiguration.sol";

contract AuraMarketDeployer is DeployConfiguration {
    struct AdaptorData {
        uint8 poolDecimals;
        bytes32 poolId;
        uint8[] rateProviderDecimals;
        address[] rateProviders;
        address[] underlyingOrConstituent;
    }
    struct AuraUnderlyingParam {
        address asset;
        address chainlinkEth;
        address chainlinkUsd;
    }
    struct AuraMarketParam {
        AdaptorData adaptorData;
        address asset;
        address booster;
        uint256 pid;
        address rewarder;
        AuraUnderlyingParam[] underlyings;
    }

    address internal constant _BALANCER_VAULT =
        0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    function _deployAuraMarket(
        string memory name,
        AuraMarketParam memory param
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
        address balancerAdaptor = _getDeployedContract("balancerAdaptor");
        if (balancerAdaptor == address(0)) {
            balancerAdaptor = address(
                new BalancerStablePoolAdaptor(
                    ICentralRegistry(centralRegistry),
                    IVault(_BALANCER_VAULT)
                )
            );
            console.log("balancerAdaptor: ", balancerAdaptor);
            _saveDeployedContracts("balancerAdaptor", balancerAdaptor);
        }

        // Setup underlying chainlink adapters
        for (uint256 i = 0; i < param.underlyings.length; i++) {
            AuraUnderlyingParam memory underlyingParam = param.underlyings[i];

            if (
                !ChainlinkAdaptor(chainlinkAdaptor).isSupportedAsset(
                    underlyingParam.asset
                )
            ) {
                if (underlyingParam.chainlinkEth != address(0)) {
                    ChainlinkAdaptor(chainlinkAdaptor).addAsset(
                        underlyingParam.asset,
                        underlyingParam.chainlinkEth,
                        0,
                        false
                    );
                }
                if (underlyingParam.chainlinkUsd != address(0)) {
                    ChainlinkAdaptor(chainlinkAdaptor).addAsset(
                        underlyingParam.asset,
                        underlyingParam.chainlinkUsd,
                        0,
                        true
                    );
                }
                console.log("chainlinkAdaptor.addAsset");
            }

            if (
                !OracleRouter(oracleRouter).isApprovedAdaptor(chainlinkAdaptor)
            ) {
                OracleRouter(oracleRouter).addApprovedAdaptor(chainlinkAdaptor);
                console.log(
                    "oracleRouter.addApprovedAdaptor: ",
                    chainlinkAdaptor
                );
            }

            try
                OracleRouter(oracleRouter).assetPriceFeeds(
                    underlyingParam.asset,
                    0
                )
            returns (address feed) {} catch {
                OracleRouter(oracleRouter).addAssetPriceFeed(
                    underlyingParam.asset,
                    chainlinkAdaptor
                );
                console.log(
                    "oracleRouter.addAssetPriceFeed: ",
                    underlyingParam.asset
                );
            }
        }

        // Deploy Balancer adapter
        if (!OracleRouter(oracleRouter).isApprovedAdaptor(balancerAdaptor)) {
            OracleRouter(oracleRouter).addApprovedAdaptor(balancerAdaptor);
            console.log("oracleRouter.addApprovedAdaptor: ", balancerAdaptor);
        }
        if (
            !BalancerStablePoolAdaptor(balancerAdaptor).isSupportedAsset(
                param.asset
            )
        ) {
            BalancerStablePoolAdaptor.AdaptorData memory adaptorData;
            adaptorData.poolId = param.adaptorData.poolId;
            adaptorData.poolDecimals = param.adaptorData.poolDecimals;
            for (
                uint256 i = 0;
                i < param.adaptorData.rateProviderDecimals.length;
                ++i
            ) {
                adaptorData.rateProviderDecimals[i] = param
                    .adaptorData
                    .rateProviderDecimals[i];
            }
            for (
                uint256 i = 0;
                i < param.adaptorData.rateProviders.length;
                ++i
            ) {
                adaptorData.rateProviders[i] = param.adaptorData.rateProviders[
                    i
                ];
            }
            for (
                uint256 i = 0;
                i < param.adaptorData.underlyingOrConstituent.length;
                ++i
            ) {
                adaptorData.underlyingOrConstituent[i] = param
                    .adaptorData
                    .underlyingOrConstituent[i];
            }

            BalancerStablePoolAdaptor(balancerAdaptor).addAsset(
                param.asset,
                adaptorData
            );
            console.log("balancerAdaptor.addAsset");
        }

        try OracleRouter(oracleRouter).assetPriceFeeds(param.asset, 0) returns (
            address feed
        ) {} catch {
            OracleRouter(oracleRouter).addAssetPriceFeed(
                param.asset,
                balancerAdaptor
            );
            console.log("oracleRouter.addAssetPriceFeed: ", param.asset);
        }

        // Deploy CToken
        address cToken = _getDeployedContract(name);
        if (cToken == address(0)) {
            cToken = address(
                new AuraCToken(
                    ICentralRegistry(centralRegistry),
                    IERC20(param.asset),
                    marketManager,
                    param.pid,
                    param.rewarder,
                    param.booster
                )
            );

            console.log("cToken: ", cToken);
            _saveDeployedContracts(name, cToken);
        }

        // followings should be done separate because it requires dust amount deposits
        // marketManager.listToken;
        // marketManager.updateCollateralToken
        // marketManager.setCTokenCollateralCaps
    }
}
