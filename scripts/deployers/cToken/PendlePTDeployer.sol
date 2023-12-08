// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { PriceRouter } from "contracts/oracles/PriceRouter.sol";
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
        uint8 underlyingDecimals;
        address underlyingAsset;
        PendlePtUnderlyingParam[] underlyings;
    }

    function deployPendlePT(
        string memory name,
        PendlePTParam memory param
    ) internal {
        address centralRegistry = getDeployedContract("centralRegistry");
        console.log("centralRegistry =", centralRegistry);
        require(centralRegistry != address(0), "Set the centralRegistry!");
        address lendtroller = getDeployedContract("lendtroller");
        console.log("lendtroller =", lendtroller);
        require(lendtroller != address(0), "Set the lendtroller!");
        address priceRouter = getDeployedContract("priceRouter");
        console.log("priceRouter =", priceRouter);
        require(priceRouter != address(0), "Set the priceRouter!");

        address chainlinkAdaptor = getDeployedContract("chainlinkAdaptor");
        if (chainlinkAdaptor == address(0)) {
            chainlinkAdaptor = address(
                new ChainlinkAdaptor(ICentralRegistry(centralRegistry))
            );
            console.log("chainlinkAdaptor: ", chainlinkAdaptor);
            saveDeployedContracts("chainlinkAdaptor", chainlinkAdaptor);
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
                        false
                    );
                }
                if (underlyingParam.chainlinkUsd != address(0)) {
                    ChainlinkAdaptor(chainlinkAdaptor).addAsset(
                        underlyingParam.asset,
                        underlyingParam.chainlinkUsd,
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

        // Deploy Pendle PT Adapter
        {
            address pendlePtAdapter = getDeployedContract("pendlePtAdapter");
            if (pendlePtAdapter == address(0)) {
                pendlePtAdapter = address(
                    new PendlePrincipalTokenAdaptor(
                        ICentralRegistry(address(centralRegistry)),
                        IPendlePTOracle(param.ptOracle)
                    )
                );
                console.log("pendlePtAdapter: ", pendlePtAdapter);
                saveDeployedContracts("pendlePtAdapter", pendlePtAdapter);
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

            if (!PriceRouter(priceRouter).isApprovedAdaptor(pendlePtAdapter)) {
                PriceRouter(priceRouter).addApprovedAdaptor(pendlePtAdapter);
                console.log(
                    "priceRouter.addApprovedAdaptor: ",
                    pendlePtAdapter
                );
            }

            try
                PriceRouter(priceRouter).assetPriceFeeds(param.asset, 0)
            returns (address feed) {} catch {
                PriceRouter(priceRouter).addAssetPriceFeed(
                    param.asset,
                    pendlePtAdapter
                );
                console.log("priceRouter.addAssetPriceFeed: ", param.asset);
            }
        }

        // Deploy CToken
        address cToken = getDeployedContract(name);
        if (cToken == address(0)) {
            cToken = address(
                new CTokenPrimitive(
                    ICentralRegistry(address(centralRegistry)),
                    IERC20(param.asset),
                    lendtroller
                )
            );

            console.log("cToken: ", cToken);
            saveDeployedContracts(name, cToken);

            if (!PriceRouter(priceRouter).isSupportedAsset(cToken)) {
                PriceRouter(priceRouter).addMTokenSupport(cToken);
            }
        }

        // followings should be done separate because it requires dust amount deposits
        // lendtroller.listToken;
        // lendtroller.updateCollateralToken
        // lendtroller.setCTokenCollateralCaps
    }
}
