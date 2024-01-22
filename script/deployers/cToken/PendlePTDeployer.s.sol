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

contract PendlePTDeployer is DeployConfiguration {
    struct PendlePtUnderlyingParam {
        address asset;
        address chainlinkEth;
        address chainlinkUsd;
    }
    struct PendlePTParam {
        address asset;
        address market;
        address ptOracle;
        uint32 twapDuration;
        address underlyingAsset;
        uint8 underlyingDecimals;
        PendlePtUnderlyingParam[] underlyings;
    }

    function _deployPendlePT(
        string memory name,
        PendlePTParam memory param
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

        // Setup underlying chainlink adapters
        for (uint256 i = 0; i < param.underlyings.length; i++) {
            PendlePtUnderlyingParam memory underlyingParam = param.underlyings[
                i
            ];

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

        // Deploy Pendle PT Adapter
        {
            address pendlePtAdapter = _getDeployedContract("pendlePtAdapter");
            if (pendlePtAdapter == address(0)) {
                pendlePtAdapter = address(
                    new PendlePrincipalTokenAdaptor(
                        ICentralRegistry(address(centralRegistry)),
                        IPendlePTOracle(param.ptOracle)
                    )
                );
                console.log("pendlePtAdapter: ", pendlePtAdapter);
                _saveDeployedContracts("pendlePtAdapter", pendlePtAdapter);
            }

            if (
                !PendlePrincipalTokenAdaptor(pendlePtAdapter).isSupportedAsset(
                    param.asset
                )
            ) {
                PendlePrincipalTokenAdaptor.AdaptorData memory adapterData;
                adapterData.market = IPMarket(param.market);
                adapterData.twapDuration = param.twapDuration;
                adapterData.quoteAsset = param.underlyingAsset;
                adapterData.quoteAssetDecimals = param.underlyingDecimals;
                PendlePrincipalTokenAdaptor(pendlePtAdapter).addAsset(
                    param.asset,
                    adapterData
                );
                console.log("pendlePtAdapter.addAsset");
            }

            if (!OracleRouter(oracleRouter).isApprovedAdaptor(pendlePtAdapter)) {
                OracleRouter(oracleRouter).addApprovedAdaptor(pendlePtAdapter);
                console.log(
                    "oracleRouter.addApprovedAdaptor: ",
                    pendlePtAdapter
                );
            }

            try
                OracleRouter(oracleRouter).assetPriceFeeds(param.asset, 0)
            returns (address feed) {} catch {
                OracleRouter(oracleRouter).addAssetPriceFeed(
                    param.asset,
                    pendlePtAdapter
                );
                console.log("oracleRouter.addAssetPriceFeed: ", param.asset);
            }
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
