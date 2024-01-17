// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { PriceRouter } from "contracts/oracles/PriceRouter.sol";
import { ChainlinkAdaptor } from "contracts/oracles/adaptors/chainlink/ChainlinkAdaptor.sol";
import { CurveAdaptor } from "contracts/oracles/adaptors/curve/CurveAdaptor.sol";
import { Convex2PoolCToken } from "contracts/market/collateral/Convex2PoolCToken.sol";
import { Convex3PoolCToken } from "contracts/market/collateral/Convex3PoolCToken.sol";
import { Convex4PoolCToken } from "contracts/market/collateral/Convex4PoolCToken.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";

import { DeployConfiguration } from "../../utils/DeployConfiguration.sol";

contract ConvexMarketDeployer is DeployConfiguration {
    struct ConvexUnderlyingParam {
        address asset;
        address chainlinkEth;
        address chainlinkUsd;
    }
    struct ConvexMarketParam {
        address asset;
        address booster;
        uint256 pid;
        address pool;
        address rewarder;
        ConvexUnderlyingParam[] underlyings;
    }

    function _deployConvexMarket(
        string memory name,
        ConvexMarketParam memory param
    ) internal {
        address centralRegistry = _getDeployedContract("centralRegistry");
        console.log("centralRegistry =", centralRegistry);
        require(centralRegistry != address(0), "Set the centralRegistry!");
        address marketManager = _getDeployedContract("marketManager");
        console.log("marketManager =", marketManager);
        require(marketManager != address(0), "Set the marketManager!");
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
        address curveAdaptor = _getDeployedContract("curveAdaptor");
        if (curveAdaptor == address(0)) {
            curveAdaptor = address(
                new CurveAdaptor(ICentralRegistry(centralRegistry))
            );
            console.log("curveAdaptor: ", curveAdaptor);
            _saveDeployedContracts("curveAdaptor", curveAdaptor);
            CurveAdaptor(curveAdaptor).setReentrancyConfig(2, 50_000);
            CurveAdaptor(curveAdaptor).setReentrancyConfig(3, 50_000);
            CurveAdaptor(curveAdaptor).setReentrancyConfig(4, 50_000);
        }

        // Setup underlying chainlink adapters
        for (uint256 i = 0; i < param.underlyings.length; i++) {
            ConvexUnderlyingParam memory underlyingParam = param.underlyings[
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

        // Deploy Curve adapter
        if (!PriceRouter(priceRouter).isApprovedAdaptor(curveAdaptor)) {
            PriceRouter(priceRouter).addApprovedAdaptor(curveAdaptor);
            console.log("priceRouter.addApprovedAdaptor: ", curveAdaptor);
        }
        if (!CurveAdaptor(curveAdaptor).isSupportedAsset(param.asset)) {
            CurveAdaptor(curveAdaptor).addAsset(param.asset, param.pool);
            console.log("curveAdaptor.addAsset");
        }
        try PriceRouter(priceRouter).assetPriceFeeds(param.asset, 0) returns (
            address feed
        ) {} catch {
            PriceRouter(priceRouter).addAssetPriceFeed(
                param.asset,
                curveAdaptor
            );
            console.log("priceRouter.addAssetPriceFeed: ", param.asset);
        }

        // Deploy CToken
        address cToken = _getDeployedContract(name);
        if (cToken == address(0)) {
            if (param.underlyings.length == 2) {
                cToken = address(
                    new Convex2PoolCToken(
                        ICentralRegistry(centralRegistry),
                        IERC20(param.asset),
                        marketManager,
                        param.pid,
                        param.rewarder,
                        param.booster
                    )
                );
            } else if (param.underlyings.length == 3) {
                cToken = address(
                    new Convex2PoolCToken(
                        ICentralRegistry(centralRegistry),
                        IERC20(param.asset),
                        marketManager,
                        param.pid,
                        param.rewarder,
                        param.booster
                    )
                );
            } else if (param.underlyings.length == 4) {
                cToken = address(
                    new Convex2PoolCToken(
                        ICentralRegistry(centralRegistry),
                        IERC20(param.asset),
                        marketManager,
                        param.pid,
                        param.rewarder,
                        param.booster
                    )
                );
            }
            console.log("cToken: ", cToken);
            _saveDeployedContracts(name, cToken);
        }

        // followings should be done separate because it requires dust amount deposits
        // marketManager.listToken;
        // marketManager.updateCollateralToken
        // marketManager.setCTokenCollateralCaps
    }
}
