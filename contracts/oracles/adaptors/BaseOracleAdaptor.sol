// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import "../../interfaces/ICentralRegistry.sol";
import "../../interfaces/IOracleAdaptor.sol";

abstract contract BaseOracleAdaptor {

    /// @notice Address for Curvance DAO registry contract for ownership and location data.
    ICentralRegistry public immutable centralRegistry;

    /// @notice Mapping used to track whether or not an asset is supported by the adaptor and pricing information.
    mapping(address => bool) public isSupportedAsset;

    // 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE this is for pricing eth in Curve

    constructor(ICentralRegistry _centralRegistry) {
        centralRegistry = _centralRegistry;
    }

    // Only callable by Price Router.
    modifier onlyPriceRouter() {
        require(
            msg.sender == centralRegistry.priceRouter(),
            "adaptor: UNAUTHORIZED"
        );
        _;
    }

    modifier onlyDaoPermissions() {
        require(centralRegistry.hasDaoPermissions(msg.sender), "centralRegistry: UNAUTHORIZED");
        _;
    }

    modifier onlyElevatedPermissions() {
            require(centralRegistry.hasElevatedPermissions(msg.sender), "centralRegistry: UNAUTHORIZED");
            _;
    }

    /// @notice Called by PriceRouter to price an asset.
    function getPrice(
        address asset,
        bool isUsd,
        bool getLower
    ) external view virtual returns (PriceReturnData memory);

    /// @notice Removes a supported asset from the adaptor.
    function removeAsset(address asset) external virtual;
}
