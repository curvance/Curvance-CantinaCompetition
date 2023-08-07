// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IOracleAdaptor, PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";

abstract contract BaseOracleAdaptor {

    /// CONSTANTS ///

    ICentralRegistry public immutable centralRegistry; // Curvance DAO hub

    /// STORAGE ///

    /// Asset => Supported by adaptor
    mapping(address => bool) public isSupportedAsset;

    /// MODIFIERS ///

    modifier onlyPriceRouter() {
        require(
            msg.sender == centralRegistry.priceRouter(),
            "Adaptor: UNAUTHORIZED"
        );
        _;
    }

    modifier onlyDaoPermissions() {
        require(
            centralRegistry.hasDaoPermissions(msg.sender),
            "CentralRegistry: UNAUTHORIZED"
        );
        _;
    }

    modifier onlyElevatedPermissions() {
        require(
            centralRegistry.hasElevatedPermissions(msg.sender),
            "CentralRegistry: UNAUTHORIZED"
        );
        _;
    }

    /// CONSTRUCTOR ///

    constructor(ICentralRegistry centralRegistry_) {
        require(
            ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            ),
            "PriceRouter: Central Registry is invalid"
        );

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
