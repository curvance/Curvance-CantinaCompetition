// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IOracleAdaptor, PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";

abstract contract BaseOracleAdaptor {

    /// CONSTANTS ///
    /// @notice Address for Curvance DAO registry contract for ownership and location data.
    ICentralRegistry public immutable centralRegistry;

    /// STORAGE ///
    /// @notice Mapping used to track whether or not an asset is supported by the adaptor and pricing information.
    mapping(address => bool) public isSupportedAsset;

    constructor(ICentralRegistry centralRegistry_) {

        require(
            ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            ),
            "priceRouter: Central Registry is invalid"
        );

        centralRegistry = centralRegistry_;
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
