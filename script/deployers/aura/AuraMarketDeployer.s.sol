// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { PriceRouter } from "contracts/oracles/PriceRouter.sol";
import { ChainlinkAdaptor } from "contracts/oracles/adaptors/chainlink/ChainlinkAdaptor.sol";
import { BalancerStablePoolAdaptor } from "contracts/oracles/adaptors/balancer/BalancerStablePoolAdaptor.sol";
import { IVault } from "contracts/oracles/adaptors/balancer/BalancerBaseAdaptor.sol";
import { AuraCToken } from "contracts/market/collateral/AuraCToken.sol";
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
                !PriceRouter(priceRouter).isApprovedAdaptor(chainlinkAdaptor)
            ) {
                PriceRouter(priceRouter).addApprovedAdaptor(chainlinkAdaptor);
                console.log(
                    "priceRouter.addApprovedAdaptor: ",
                    chainlinkAdaptor
                );
            }

            try
                PriceRouter(priceRouter).assetPriceFeeds(
                    underlyingParam.asset,
                    0
                )
            returns (address feed) {} catch {
                PriceRouter(priceRouter).addAssetPriceFeed(
                    underlyingParam.asset,
                    chainlinkAdaptor
                );
                console.log(
                    "priceRouter.addAssetPriceFeed: ",
                    underlyingParam.asset
                );
            }
        }

        // Deploy Balancer adapter
        if (!PriceRouter(priceRouter).isApprovedAdaptor(balancerAdaptor)) {
            PriceRouter(priceRouter).addApprovedAdaptor(balancerAdaptor);
            console.log("priceRouter.addApprovedAdaptor: ", balancerAdaptor);
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

        try PriceRouter(priceRouter).assetPriceFeeds(param.asset, 0) returns (
            address feed
        ) {} catch {
            PriceRouter(priceRouter).addAssetPriceFeed(
                param.asset,
                balancerAdaptor
            );
            console.log("priceRouter.addAssetPriceFeed: ", param.asset);
        }

        // Deploy CToken
        address cToken = _getDeployedContract(name);
        if (cToken == address(0)) {
            cToken = address(
                new AuraCToken(
                    ICentralRegistry(centralRegistry),
                    IERC20(param.asset),
                    lendtroller,
                    param.pid,
                    param.rewarder,
                    param.booster
                )
            );

            console.log("cToken: ", cToken);
            _saveDeployedContracts(name, cToken);
        }

        // followings should be done separate because it requires dust amount deposits
        // lendtroller.listToken;
        // lendtroller.updateCollateralToken
        // lendtroller.setCTokenCollateralCaps
    }
}
