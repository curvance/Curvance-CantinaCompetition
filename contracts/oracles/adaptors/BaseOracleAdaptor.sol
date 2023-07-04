// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IOracleAdaptor, PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";

abstract contract BaseOracleAdaptor is IOracleAdaptor {
    /// @notice Determines whether the adaptor reports asset prices in USD(true) or ETH(false).
    bool public isUsd;

    /**
     * @notice Address for Curvance DAO registry contract for ownership and location data.
     */
    ICentralRegistry public immutable centralRegistry;

    /**
     * @notice Mapping used to track whether or not an asset is supported by the adaptor and pricing information.
     */
    mapping(address => bool) public override isSupportedAsset;

    //0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE this is for pricing eth in Curve

    constructor(ICentralRegistry _centralRegistry) {
        centralRegistry = _centralRegistry;
        isUsd = true;
    }

    // Only callable by Price Router.
    modifier onlyPriceRouter() {
        require(
            msg.sender == centralRegistry.priceRouter(),
            "adaptor: UNAUTHORIZED"
        );
        _;
    }

    // Only callable by DAO
    modifier onlyDaoManager() {
        require(
            msg.sender == centralRegistry.daoAddress(),
            "priceRouter: UNAUTHORIZED"
        );
        _;
    }

    /**
     * @notice Called by PriceRouter to price an asset.
     */
    function getPrice(
        address _asset
    ) external view virtual override returns (PriceReturnData memory);

    /**
     * @notice Adds a new supported asset to the adaptor, can also configure sub assets that the parent asset contain.
     */
    function addAsset(address _asset) external virtual {}

    /**
     * @notice Removes a supported asset from the adaptor.
     */
    function removeAsset(address _asset) external virtual;
}
