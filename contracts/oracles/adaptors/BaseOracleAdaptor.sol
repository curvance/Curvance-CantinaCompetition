// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";

abstract contract BaseOracleAdaptor {
    /// CONSTANTS ///

    ICentralRegistry public immutable centralRegistry; // Curvance DAO hub

    /// STORAGE ///

    /// Asset => Supported by adaptor
    mapping(address => bool) public isSupportedAsset;

    /// ERRORS ///

    error BaseOracleAdaptor__Unauthorized();
    error BaseOracleAdaptor__InvalidCentralRegistry();

    /// MODIFIERS ///

    modifier onlyPriceRouter() {
        if (msg.sender != centralRegistry.priceRouter()) {
            revert BaseOracleAdaptor__Unauthorized();
        }
        _;
    }

    modifier onlyDaoPermissions() {
        if (!centralRegistry.hasDaoPermissions(msg.sender)) {
            revert BaseOracleAdaptor__Unauthorized();
        }
        _;
    }

    modifier onlyElevatedPermissions() {
        if (!centralRegistry.hasElevatedPermissions(msg.sender)) {
            revert BaseOracleAdaptor__Unauthorized();
        }
        _;
    }

    /// CONSTRUCTOR ///

    constructor(ICentralRegistry centralRegistry_) {
        if (
            !ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            )
        ) {
            revert BaseOracleAdaptor__InvalidCentralRegistry();
        }

        centralRegistry = centralRegistry_;
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Called by PriceRouter to price an asset.
    function getPrice(
        address asset,
        bool inUSD,
        bool getLower
    ) external view virtual returns (PriceReturnData memory);

    /// @notice Removes a supported asset from the adaptor.
    function removeAsset(address asset) external virtual;
}
