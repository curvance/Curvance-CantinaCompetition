// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import { BalancerPoolAdaptor, IVault } from "./BalancerPoolAdaptor.sol";
import { IBalancerPool } from "contracts/interfaces/external/balancer/IBalancerPool.sol";
import { IRateProvider } from "contracts/interfaces/external/balancer/IRateProvider.sol";
import { IOracleAdaptor, PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { PriceRouter } from "contracts/oracles/PriceRouterV2.sol";

contract BalancerStablePoolAdaptor is BalancerPoolAdaptor {
    constructor(
        ICentralRegistry _centralRegistry,
        IVault _balancerVault,
        bool _isUsd
    ) BalancerPoolAdaptor(_centralRegistry, _balancerVault, _isUsd) {}

    /**
     * @notice Adaptor storage
     * @param poolId the pool id of the BPT being priced
     * @param poolDecimals the decimals of the BPT being priced
     * @param rateProviders array of rate providers for each constituent
     *        a zero address rate provider means we are using an underlying correlated to the
     *        pools virtual base.
     * @param underlyingOrConstituent the ERC20 underlying asset or the constituent in the pool
     * @dev Only use the underlying asset, if the underlying is correlated to the pools virtual base.
     */
    struct AdaptorData {
        bytes32 poolId;
        uint8 poolDecimals;
        uint8[8] rateProviderDecimals;
        address[8] rateProviders;
        address[8] underlyingOrConstituent;
    }

    /**
     * @notice Balancer Stable Pool Adaptor Storage
     */
    mapping(address => AdaptorData) public adaptorData;

    /**
     * @notice Add a Balancer Stable Pool Bpt as an asset.
     * @dev Should be called before `PriceRotuer:addAssetPriceFeed` is called.
     * @param _asset the address of the bpt to add
     * @param _data AdaptorData needed to add `_asset`
     */
    function addAsset(
        address _asset,
        AdaptorData memory _data
    ) external onlyDaoManager {
        require(
            !isSupportedAsset[_asset],
            "BalancerStablePoolAdaptor: asset already supported"
        );
        IBalancerPool pool = IBalancerPool(_asset);

        // Grab the poolId and decimals.
        _data.poolId = pool.getPoolId();
        _data.poolDecimals = pool.decimals();

        PriceRouter priceRouter = PriceRouter(centralRegistry.priceRouter());

        uint256 numUnderlyingOrConstituent = _data
            .underlyingOrConstituent
            .length;

        // Make sure we can price all underlying tokens.
        for (uint256 i; i < numUnderlyingOrConstituent; ++i) {
            // Break when a zero address is found.
            if (address(_data.underlyingOrConstituent[i]) == address(0)) break;
            require(
                priceRouter.isSupportedAsset(_data.underlyingOrConstituent[i]),
                "BalancerStablePoolAdaptor: unsupported dependent"
            );
            if (_data.rateProviders[i] != address(0)) {
                // Make sure decimals were provided.
                require(
                    _data.rateProviderDecimals[i] > 0,
                    "BalancerStablePoolAdaptor: rate decimals zero"
                );
                // Make sure we can call it and get a non zero value.
                uint256 rate = IRateProvider(_data.rateProviders[i]).getRate();
                require(rate > 0, "BalancerStablePoolAdaptor: zero rate");
            }
        }

        // Save values in Adaptor storage.
        adaptorData[_asset] = _data;
        isSupportedAsset[_asset] = true;
    }

    /**
     * @notice Called during pricing operations.
     * @param _asset the bpt being priced
     * @param _isUsd indicates whether we want the price in USD or ETH
     * @param _getLower Since this adaptor calls back into the price router
     *                  it needs to know if it should be working with the upper
     *                  or lower prices of assets
     */
    function getPrice(
        address _asset,
        bool _isUsd,
        bool _getLower
    ) external view override returns (PriceReturnData memory pData) {
        require(
            isSupportedAsset[_asset],
            "BalancerStablePoolAdaptor: asset not supported"
        );
        _ensureNotInVaultContext(balancerVault);
        // Read Adaptor storage and grab pool tokens
        AdaptorData memory data = adaptorData[_asset];
        IBalancerPool pool = IBalancerPool(_asset);

        pData.inUSD = _isUsd;
        PriceRouter priceRouter = PriceRouter(centralRegistry.priceRouter());
        uint256 BAD_SOURCE = priceRouter.BAD_SOURCE();

        // Find the minimum price of all the pool tokens.
        uint256 numUnderlyingOrConstituent = data
            .underlyingOrConstituent
            .length;
        uint256 minPrice = type(uint256).max;
        uint256 price;
        uint256 errorCode;
        for (uint256 i; i < numUnderlyingOrConstituent; ++i) {
            // Break when a zero address is found.
            if (address(data.underlyingOrConstituent[i]) == address(0)) break;
            (price, errorCode) = priceRouter.getPrice(
                data.underlyingOrConstituent[i],
                _isUsd,
                _getLower
            );
            if (errorCode > 0) {
                pData.hadError = true;
                // If error code is BAD_SOURCE we can't use this price at all so continue.
                if (errorCode == BAD_SOURCE) continue;
            }
            if (data.rateProviders[i] != address(0)) {
                uint256 rate = IRateProvider(data.rateProviders[i]).getRate();
                price = (price * 10 ** data.rateProviderDecimals[i]) / rate;
            }
            if (price < minPrice) minPrice = price;
        }

        if (minPrice == type(uint256).max) pData.hadError = true;
        else {
            pData.price = uint240(
                (price * pool.getRate()) / 10 ** data.poolDecimals
            );
        }
    }

    /**
     * @notice Removes a supported asset from the adaptor.
     * @dev Calls back into price router to notify it of its removal
     */
    function removeAsset(address _asset) external override onlyDaoManager {
        require(
            isSupportedAsset[_asset],
            "BalancerStablePoolAdaptor: asset not supported"
        );
        PriceRouter priceRouter = PriceRouter(centralRegistry.priceRouter());
        isSupportedAsset[_asset] = false;
        delete adaptorData[_asset];
        priceRouter.notifyAssetPriceFeedRemoval(_asset);
    }
}
