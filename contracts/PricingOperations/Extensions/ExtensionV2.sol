// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import "../../interfaces/ICentralRegistry.sol";
import "../../interfaces/IOracleExtension.sol";

abstract contract Extension {

    struct assetData {
        address[] subAssets;
        address pool;
        address asset;
    }

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
     * @notice Mapping used to track whether or not an asset is supported by the extension and pricing information.
     */
    mapping(address => assetData) public assets;

    //0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE this is for pricing eth in Curve

    constructor(ICentralRegistry _centralRegistry) {
        centralRegistry = _centralRegistry;
    }

    // Only callable by Price Router.
    modifier onlyPriceRouter() {
        require(msg.sender == centralRegistry.priceRouter(), "extension: UNAUTHORIZED");
        _;
    }

    /**
     * @notice Called by PriceRouter to price an asset.
     */
    function getPrice(address _asset) external view virtual returns (priceReturnData calldata);

    /**
     * @notice Adds a new supported asset to the extension, can also configure sub assets that the parent asset contain.
     */
    function addAsset(address _asset) external virtual;

    /**
     * @notice Removes a supported asset from the extension.
     */
    function removeAsset(address _asset) external virtual;

}
