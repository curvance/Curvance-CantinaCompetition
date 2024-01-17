// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { OracleRouter } from "contracts/oracles/OracleRouter.sol";
import { ChainlinkAdaptor } from "contracts/oracles/adaptors/chainlink/ChainlinkAdaptor.sol";
import { BalancerStablePoolAdaptor } from "contracts/oracles/adaptors/balancer/BalancerStablePoolAdaptor.sol";
import { IVault } from "contracts/oracles/adaptors/balancer/BalancerBaseAdaptor.sol";
import { DToken } from "contracts/market/collateral/DToken.sol";
import { DynamicInterestRateModel } from "contracts/market/DynamicInterestRateModel.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";

import { DeployConfiguration } from "../../utils/DeployConfiguration.sol";

contract DTokenDeployer is DeployConfiguration {
    struct DTokenInterestRateParam {
        uint256 adjustmentRate;
        uint256 adjustmentVelocity;
        uint256 baseRatePerYear;
        uint256 decayRate;
        uint256 vertexMultiplierMax;
        uint256 vertexRatePerYear;
        uint256 vertexUtilizationStart;
    }
    struct DTokenParam {
        address asset;
        address chainlinkEth;
        address chainlinkUsd;
        DTokenInterestRateParam interestRateParam;
    }

    function _deployDToken(
        string memory name,
        DTokenParam memory param
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

        // Setup chainlink adapters
        if (
            !ChainlinkAdaptor(chainlinkAdaptor).isSupportedAsset(param.asset)
        ) {
            if (param.chainlinkEth != address(0)) {
                ChainlinkAdaptor(chainlinkAdaptor).addAsset(
                    param.asset,
                    param.chainlinkEth,
                    0,
                    false
                );
            }
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

        // Deploy DToken
        address dToken = _getDeployedContract(name);
        if (dToken == address(0)) {
            address interestRateModel = address(
                new DynamicInterestRateModel(
                    ICentralRegistry(centralRegistry),
                    param.interestRateParam.baseRatePerYear,
                    param.interestRateParam.vertexRatePerYear,
                    param.interestRateParam.vertexUtilizationStart,
                    param.interestRateParam.adjustmentRate,
                    param.interestRateParam.adjustmentVelocity,
                    param.interestRateParam.vertexMultiplierMax,
                    param.interestRateParam.decayRate
                )
            );
            console.log("interestRateModel: ", interestRateModel);

            dToken = address(
                new DToken(
                    ICentralRegistry(address(centralRegistry)),
                    param.asset,
                    marketManager,
                    interestRateModel
                )
            );

            console.log("dToken: ", dToken);
            _saveDeployedContracts(name, dToken);

            if (!OracleRouter(oracleRouter).isSupportedAsset(dToken)) {
                OracleRouter(oracleRouter).addMTokenSupport(dToken);
            }
        }

        // followings should be done separate because it requires dust amount deposits
        // marketManager.listToken;
    }
}
