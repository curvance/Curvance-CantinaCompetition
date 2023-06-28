// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import { BaseOracleAdaptor, BalancerPoolExtension, IVault, IERC20 } from "./BalancerPoolExtension.sol";
import { Math } from "contracts/libraries/Math.sol";
import { IBalancerPool } from "contracts/interfaces/external/balancer/IBalancerPool.sol";
import { IRateProvider } from "contracts/interfaces/external/balancer/IRateProvider.sol";
import { IOracleAdaptor, priceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

/**
 * @title Sommelier Price Router Balancer Stable Pool Extension
 * @notice Allows the Price Router to price Balancer Stable pool BPTs.
 * @author crispymangoes
 */
contract BalancerStablePoolExtension is BalancerPoolExtension {
    using Math for uint256;

    /**
     * @notice Atleast one of the pools underlying tokens is not supported by the Price Router.
     */
    error BalancerStablePoolExtension__PoolTokensMustBeSupported(address unsupportedAsset);

    /**
     * @notice Failed to find a minimum price for the pool tokens.
     */
    error BalancerStablePoolExtension__MinimumPriceNotFound();

    /**
     * @notice Failed to get rate from rate provider.
     */
    error BalancerStablePoolExtension__RateProviderCallFailed();

    /**
     * @notice Rate provider decimals not provided.
     */
    error BalancerStablePoolExtension__RateProviderDecimalsNotProvided();

    constructor(ICentralRegistry _centralRegistry, IVault _balancerVault) BalancerPoolExtension(_centralRegistry, _balancerVault) {}

    /**
     * @notice Extension storage
     * @param poolId the pool id of the BPT being priced
     * @param asset the address of the BPT
     * @param poolDecimals the decimals of the BPT being priced
     * @param rateProviders array of rate providers for each constituent
     *        a zero address rate provider means we are using an underlying correlated to the
     *        pools virtual base.
     * @param underlyingOrConstituent the ERC20 underlying asset or the constituent in the pool
     * @dev Only use the underlying asset, if the underlying is correlated to the pools virtual base.
     */
    struct ExtensionStorage {
        bytes32 poolId;
        address asset;
        uint8 poolDecimals;
        uint8[8] rateProviderDecimals;
        address[8] rateProviders;
        address[8] underlyingOrConstituent;
    }

    /**
     * @notice Balancer Stable Pool Extension Storage
     */
    mapping(uint64 => ExtensionStorage) public extensionStorage;

    /**
     * @notice Called by the price router during `_updateAsset` calls.
     * @param _storage the abi encoded ExtensionStorage.
     * @dev _storage will have its poolId, and poolDecimals over written, but
     *      rateProviderDecimals, rateProviders, and underlyingOrConstituent
     *      MUST be correct, providing wrong values will result in inaccurate pricing.
     */
    function setupSource(address, uint64 _sourceId, bytes memory _storage) external onlyPriceRouter {
        ExtensionStorage memory stor = abi.decode(_storage, (ExtensionStorage));
        IBalancerPool pool = IBalancerPool(stor.asset);

        // Grab the poolId and decimals.
        stor.poolId = pool.getPoolId();
        stor.poolDecimals = pool.decimals();

        // Make sure we can price all underlying tokens.
        for (uint256 i; i < stor.underlyingOrConstituent.length; ++i) {
            // Break when a zero address is found.
            if (address(stor.underlyingOrConstituent[i]) == address(0)) break;
            if (!centralRegistry.priceRouter().isSupported(stor.underlyingOrConstituent[i]))
            //    revert BalancerStablePoolExtension__PoolTokensMustBeSupported(stor.underlyingOrConstituent[i]);
            if (stor.rateProviders[i] != address(0)) {
                // Make sure decimals were provided.
                if (stor.rateProviderDecimals[i] == 0)
                    revert BalancerStablePoolExtension__RateProviderDecimalsNotProvided();
                // Make sure we can call it and get a non zero value.
                uint256 rate = IRateProvider(stor.rateProviders[i]).getRate();
                if (rate == 0) revert BalancerStablePoolExtension__RateProviderCallFailed();
            }
        }

        // Save values in extension storage.
        extensionStorage[_sourceId] = stor;
    }

    /**
     * @notice Called during pricing operations.
     */
    function getPriceInBase(
        uint64 sourceId
    ) external view returns (uint256 upper, uint256 lower, uint8 errorCode) {
        _ensureNotInVaultContext(balancerVault);
        // Read extension storage and grab pool tokens
        ExtensionStorage memory stor = extensionStorage[sourceId];
        IBalancerPool pool = IBalancerPool(stor.asset);

        // Find the minimum price of all the pool tokens.
        uint256 minUpperPrice = type(uint256).max;
        uint256 minLowerPrice = type(uint256).max;
        uint256 _upper;
        uint256 _lower;
        uint8 _errorCode;
        for (uint256 i; i < stor.underlyingOrConstituent.length; ++i) {
            // Break when a zero address is found.
            if (address(stor.underlyingOrConstituent[i]) == address(0)) break;
            (_upper, _lower, _errorCode) = centralRegistry.priceRouter().getPriceInBase(stor.underlyingOrConstituent[i]);
            if (_errorCode == BAD_SOURCE) {
                // Extension is blind to real `underlyingOrConstituentPrice`, so return an error code of BAS_SOURCE.
                return (0, 0, BAD_SOURCE);
            } else if (_errorCode == CAUTION) {
                // Need to update errorCode.
                errorCode = CAUTION;
            }
            if (stor.rateProviders[i] != address(0)) {
                uint256 rate = IRateProvider(stor.rateProviders[i]).getRate();
                _upper = _upper.mulDivDown(10 ** stor.rateProviderDecimals[i], rate);
                _lower = _lower.mulDivDown(10 ** stor.rateProviderDecimals[i], rate);
            }
            if (_upper < minUpperPrice) minUpperPrice = _upper;
            if (_lower > 0 && _lower < minLowerPrice) minLowerPrice = _lower;
        }

        // TODO is it okay if lower is still zero?
        if (minUpperPrice == type(uint256).max) return (0, 0, BAD_SOURCE);

        uint256 poolRate = pool.getRate();
        upper = minUpperPrice.mulDivDown(poolRate, 10 ** stor.poolDecimals);
        lower = minLowerPrice.mulDivDown(poolRate, 10 ** stor.poolDecimals);
    }

    /**
     * @notice Called by PriceRouter to price an asset.
     */
    function getPrice(address _asset) external view override returns (priceReturnData memory) {
        priceReturnData memory data = priceReturnData({price:0, hadError:false, inUSD:false});
        return data;
    }

    /**
     * @notice Adds a new supported asset to the adaptor, can also configure sub assets that the parent asset contain.
     */
    function addAsset(address _asset) external override {}

    /**
     * @notice Removes a supported asset from the adaptor.
     */
    function removeAsset(address _asset) external override {}
}
