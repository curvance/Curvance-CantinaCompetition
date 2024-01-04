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

    /// INTERNAL FUNCTIONS ///

    function _checkOracleOverflow(uint256 price) internal pure returns (bool) {
        return price > type(uint240).max;
    }

    /// @dev Checks whether the caller has sufficient permissioning.
    function _checkDaoPermissions() internal view {
        if (!centralRegistry.hasDaoPermissions(msg.sender)) {
            revert BaseOracleAdaptor__Unauthorized();
        }
    }

    /// @dev Checks whether the caller has sufficient permissioning.
    function _checkElevatedPermissions() internal view {
        if (!centralRegistry.hasElevatedPermissions(msg.sender)) {
            revert BaseOracleAdaptor__Unauthorized();
        }
    }

    function _checkIsPriceRouter() internal view {
        if (msg.sender != centralRegistry.priceRouter()) {
            revert BaseOracleAdaptor__Unauthorized();
        }
    }

    /// FUNCTIONS TO OVERRIDE ///

    /// @notice Removes a supported asset from the adaptor.
    function removeAsset(address asset) external virtual;
}
