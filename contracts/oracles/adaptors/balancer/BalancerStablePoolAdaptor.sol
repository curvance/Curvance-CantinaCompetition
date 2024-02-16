// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { BalancerBaseAdaptor, IVault } from "contracts/oracles/adaptors/balancer/BalancerBaseAdaptor.sol";
import { WAD, BAD_SOURCE } from "contracts/libraries/Constants.sol";

import { IBalancerPool } from "contracts/interfaces/external/balancer/IBalancerPool.sol";
import { IRateProvider } from "contracts/interfaces/external/balancer/IRateProvider.sol";
import { PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IOracleRouter } from "contracts/interfaces/IOracleRouter.sol";

contract BalancerStablePoolAdaptor is BalancerBaseAdaptor {
    /// TYPES ///

    /// @notice Stores configuration data for Balance BPT pricing.
    /// @dev Only use the underlying asset, if the underlying is correlated
    ///      to the pools virtual base.
    /// @param poolId The pool id of the BPT being priced.
    /// @param poolDecimals The decimals of the BPT being priced.
    /// @param rateProviders Array of rate providers for each constituent,
    ///        a zero address rate provider means we are using an underlying
    ///        correlated to the pools virtual base.
    /// @param underlyingOrConstituent The ERC20 underlying asset or
    ///                                the constituent in the pool.
    struct AdaptorData {
        bytes32 poolId;
        uint8 poolDecimals;
        uint8[8] rateProviderDecimals;
        address[8] rateProviders;
        address[8] underlyingOrConstituent;
    }

    /// STORAGE ///

    /// @notice Adaptor configuration data for pricing an asset.
    /// @dev Balancer stable pool address => AdaptorData.
    mapping(address => AdaptorData) public adaptorData;

    /// EVENTS ///

    event BalancerStablePoolAssetAdded(
        address asset, 
        AdaptorData assetConfig, 
        bool isUpdate
    );
    event BalancerStablePoolAssetRemoved(address asset);

    /// ERRORS ///

    error BalancerStablePoolAdaptor__AssetIsNotSupported();
    error BalancerStablePoolAdaptor__ConfigurationError();

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        IVault balancerVault_
    ) BalancerBaseAdaptor(centralRegistry_, balancerVault_) {}

    /// EXTERNAL FUNCTIONS ///

    /// @notice Retrieves the price of a given BPT.
    /// @dev Price is returned in USD or ETH depending on 'inUSD' parameter.
    /// @param asset The address of the asset for which the price is needed.
    /// @param inUSD A boolean to determine if the price should be returned in
    ///              USD or not.
    /// @param getLower A boolean to determine if lower of two oracle prices
    ///                 should be retrieved.
    /// @return pData A structure containing the price, error status,
    ///                         and the quote format of the price.
    function getPrice(
        address asset,
        bool inUSD,
        bool getLower
    ) external view override returns (PriceReturnData memory pData) {
        // Validate we support pricing `asset`.
        if (!isSupportedAsset[asset]) {
            revert BalancerStablePoolAdaptor__AssetIsNotSupported();
        }

        // Validate that the vault is not being reentered.
        _ensureNotInVaultContext(balancerVault);

        // Cache adaptor data.
        AdaptorData memory data = adaptorData[asset];
        IBalancerPool pool = IBalancerPool(asset);

        pData.inUSD = inUSD;
        IOracleRouter oracleRouter = IOracleRouter(centralRegistry.oracleRouter());

        // Find the minimum price of all the pool tokens.
        uint256 numUnderlyingOrConstituent = data
            .underlyingOrConstituent
            .length;
        uint256 averagePrice;
        uint256 numPrices;

        uint256 price;
        uint256 errorCode;
        for (uint256 i; i < numUnderlyingOrConstituent; ++i) {
            // Break when a zero address is found.
            if (address(data.underlyingOrConstituent[i]) == address(0)) {
                break;
            }

            (price, errorCode) = oracleRouter.getPrice(
                data.underlyingOrConstituent[i],
                inUSD,
                getLower
            );

            // If we had an error pricing the quote asset, bubble up an error.
            if (errorCode > 0) {
                pData.hadError = true;
                return pData;
            } 
            
            // We did not have an error, so we can add the price
            // to the average, and increment number of prices.
            averagePrice += price;
            ++numPrices;
            
        }

        // If we were not able to price anything, bubble up an error.
        if (averagePrice == 0) {
            pData.hadError = true;
            return pData;
        } 

        averagePrice = ((averagePrice / numPrices) * pool.getRate()) / WAD;
        
        // Validate price will not overflow on conversion to uint240.
        if (_checkOracleOverflow(averagePrice)) {
            pData.hadError = true;
            return pData;
        }

        pData.price = uint240(averagePrice);
    }

    /// @notice Adds pricing support for `asset`, a new Balancer BPT.
    /// @dev Should be called before `OracleRouter:addAssetPriceFeed`
    ///      is called.
    /// @param asset The address of the BPT to add pricing support for.
    /// @param data The adaptor data needed to add `asset`.
    function addAsset(address asset, AdaptorData memory data) external {
        _checkElevatedPermissions();

        IBalancerPool pool = IBalancerPool(asset);

        // Query the poolId and decimals from the pool contract.
        data.poolId = pool.getPoolId();
        data.poolDecimals = pool.decimals();

        uint256 numUnderlyingOrConstituent = data
            .underlyingOrConstituent
            .length;

        // Make sure we can price all underlying tokens.
        for (uint256 i; i < numUnderlyingOrConstituent; ++i) {
            // Continue when a zero address is found.
            if (address(data.underlyingOrConstituent[i]) == address(0)) {
                continue;
            }

            if (
                !IOracleRouter(centralRegistry.oracleRouter()).isSupportedAsset(
                    data.underlyingOrConstituent[i]
                )
            ) {
                revert BalancerStablePoolAdaptor__ConfigurationError();
            }

            if (data.rateProviders[i] != address(0)) {
                // Make sure decimals were provided.
                if (data.rateProviderDecimals[i] == 0) {
                    revert BalancerStablePoolAdaptor__ConfigurationError();
                }

                // Make sure we can call it and get a non zero value.
                if (IRateProvider(data.rateProviders[i]).getRate() == 0) {
                    revert BalancerStablePoolAdaptor__ConfigurationError();
                }
            }
        }

        // Save adaptor data and update mapping that we support `asset` now.
        adaptorData[asset] = data;

        // Check whether this is new or updated support for `asset`.
        bool isUpdate;
        if (isSupportedAsset[asset]) {
            isUpdate = true;
        }

        isSupportedAsset[asset] = true;
        emit BalancerStablePoolAssetAdded(asset, data, isUpdate);
    }

    /// @notice Removes a supported asset from the adaptor.
    /// @dev Calls back into Oracle Router to notify it of its removal.
    ///      Requires that `asset` is currently supported.
    /// @param asset The address of the supported asset to remove from
    ///              the adaptor.
    function removeAsset(address asset) external override {
        _checkElevatedPermissions();

        // Validate that `asset` is currently supported.
        if (!isSupportedAsset[asset]) {
            revert BalancerStablePoolAdaptor__AssetIsNotSupported();
        }

        // Wipe config mapping entries for a gas refund.
        // Notify the adaptor to stop supporting the asset.
        delete isSupportedAsset[asset];
        delete adaptorData[asset];

        // Notify the Oracle Router that we are going to stop supporting
        // the asset.
        IOracleRouter(centralRegistry.oracleRouter()).notifyFeedRemoval(asset);
        emit BalancerStablePoolAssetRemoved(asset);
    }
}
