// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import { ERC20 } from "contracts/base/ERC20.sol";
import { PriceOps } from "contracts/PricingOperations/PriceOps.sol";
import { Math } from "contracts/utils/Math.sol";

abstract contract Extension {
    error Extension__OnlyPriceOps();

    // Only callable by priceops.
    modifier onlyPriceOps() {
        if (msg.sender != address(priceOps)) revert Extension__OnlyPriceOps();
        _;
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

    PriceOps public immutable priceOps;

    constructor(PriceOps _priceOps) {
        priceOps = _priceOps;
    }

    /**
     * @notice Called by PriceOps to setup the source.
     */
    function setupSource(address asset, uint64 sourceId, bytes memory sourceData) external virtual;

    /**
     * @notice Called by PriceOps to price an asset using the source.
     */
    function getPriceInBase(uint64 sourceId) external view virtual returns (uint256, uint256, uint8);
}
