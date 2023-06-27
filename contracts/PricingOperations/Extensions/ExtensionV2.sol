// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import "../interfaces/ICentralRegistry.sol";
import "../interfaces/IOracleExtension.sol";

abstract contract Extension {
    /**
     * @notice Error code for no error.
     */
    uint8 public constant NO_ERROR = 0;

    /**
     * @notice Error code for caution.
     */
    uint8 public constant CAUTION = 1;

    /**
     * @notice Error code for bad source.
     */
    uint8 public constant BAD_SOURCE = 2;

    ICentralRegistry public immutable centralRegistry;

    /**
     * @notice Mapping used to track whether or not an asset is supported by the extension.
     */
    mapping(address => bool) public isSupportedAsset;

    /**
     * @notice Mapping used to track whether an asset is composed of sub assets, such as LP tokens.
     */
    mapping(address => address[]) public hasSubAssets;

    constructor(ICentralRegistry _centralRegistry) {
        centralRegistry = _centralRegistry;
    }

    // Only callable by Price Router.
    modifier onlyPriceRouter() {
        require(
            msg.sender == centralRegistry.priceRouter(),
            "extension: UNAUTHORIZED"
        );
        _;
    }

    /**
     * @notice Called by PriceRouter to price an asset.
     */
    function getPrice(address _asset)
        external
        view
        virtual
        returns (priceReturnData calldata);
}
