// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { PriceRouter } from "contracts/oracles/PriceRouter.sol";
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

            if (!PriceRouter(priceRouter).isApprovedAdaptor(pendleLpAdapter)) {
                PriceRouter(priceRouter).addApprovedAdaptor(pendleLpAdapter);
                console.log(
                    "priceRouter.addApprovedAdaptor: ",
                    pendleLpAdapter
                );
            }

            try
                PriceRouter(priceRouter).assetPriceFeeds(param.asset, 0)
            returns (address feed) {} catch {
                PriceRouter(priceRouter).addAssetPriceFeed(
                    param.asset,
                    pendleLpAdapter
                );
                console.log("priceRouter.addAssetPriceFeed: ", param.asset);
            }
        }

        // Deploy CToken
        address cToken = _getDeployedContract(name);
        if (cToken == address(0)) {
            cToken = address(
                new PendleLPCToken(
                    ICentralRegistry(address(centralRegistry)),
                    IERC20(param.asset),
                    lendtroller,
                    IPendleRouter(param.router)
                )
            );

            console.log("cToken: ", cToken);
            _saveDeployedContracts(name, cToken);

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
