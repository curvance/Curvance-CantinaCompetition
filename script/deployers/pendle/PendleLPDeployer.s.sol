// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { OracleRouter } from "contracts/oracles/OracleRouter.sol";
import { ChainlinkAdaptor } from "contracts/oracles/adaptors/chainlink/ChainlinkAdaptor.sol";
import { BalancerStablePoolAdaptor } from "contracts/oracles/adaptors/balancer/BalancerStablePoolAdaptor.sol";
import { IVault } from "contracts/oracles/adaptors/balancer/BalancerBaseAdaptor.sol";
import { PendleLPCToken } from "contracts/market/collateral/PendleLPCToken.sol";
import { PendleLPTokenAdaptor } from "contracts/oracles/adaptors/pendle/PendleLPTokenAdaptor.sol";
import { IPendlePTOracle } from "contracts/interfaces/external/pendle/IPendlePtOracle.sol";
import { IPendleRouter } from "contracts/interfaces/external/pendle/IPendleRouter.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IPMarket } from "contracts/interfaces/external/pendle/IPMarket.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";

import { DeployConfiguration } from "../../utils/DeployConfiguration.sol";

contract PendleLPDeployer is DeployConfiguration {
    struct PendleLPUnderlyingParam {
        address asset;
        address chainlinkEth;
        address chainlinkUsd;
    }
    struct PendleLPParam {
        address asset;
        address pt;
        address ptOracle;
        address router;
        uint32 twapDuration;
        address underlyingAsset;
        uint8 underlyingDecimals;
        PendleLPUnderlyingParam[] underlyings;
    }

    function _deployPendleLP(
        string memory name,
        PendleLPParam memory param
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
            PendleLPUnderlyingParam memory underlyingParam = param.underlyings[
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

        // Deploy Pendle LP Adapter
        {
            address pendleLpAdapter = _getDeployedContract("pendleLpAdapter");
            if (pendleLpAdapter == address(0)) {
                pendleLpAdapter = address(
                    new PendleLPTokenAdaptor(
                        ICentralRegistry(address(centralRegistry)),
                        IPendlePTOracle(param.ptOracle)
                    )
                );
                console.log("pendleLpAdapter: ", pendleLpAdapter);
                _saveDeployedContracts("pendleLpAdapter", pendleLpAdapter);
            }

            if (
                !PendleLPTokenAdaptor(pendleLpAdapter).isSupportedAsset(
                    param.asset
                )
            ) {
                PendleLPTokenAdaptor.AdaptorData memory adapterData;
                adapterData.twapDuration = param.twapDuration;
                adapterData.pt = param.pt;
                adapterData.quoteAsset = param.underlyingAsset;
                adapterData.quoteAssetDecimals = param.underlyingDecimals;
                PendleLPTokenAdaptor(pendleLpAdapter).addAsset(
                    param.asset,
                    adapterData
                );
                console.log("pendleLpAdapter.addAsset");
            }

            if (!OracleRouter(oracleRouter).isApprovedAdaptor(pendleLpAdapter)) {
                OracleRouter(oracleRouter).addApprovedAdaptor(pendleLpAdapter);
                console.log(
                    "oracleRouter.addApprovedAdaptor: ",
                    pendleLpAdapter
                );
            }

            try
                OracleRouter(oracleRouter).assetPriceFeeds(param.asset, 0)
            returns (address feed) {} catch {
                OracleRouter(oracleRouter).addAssetPriceFeed(
                    param.asset,
                    pendleLpAdapter
                );
                console.log("oracleRouter.addAssetPriceFeed: ", param.asset);
            }
        }

        // Deploy CToken
        address cToken = _getDeployedContract(name);
        if (cToken == address(0)) {
            cToken = address(
                new PendleLPCToken(
                    ICentralRegistry(address(centralRegistry)),
                    IERC20(param.asset),
                    marketManager,
                    IPendleRouter(param.router)
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
