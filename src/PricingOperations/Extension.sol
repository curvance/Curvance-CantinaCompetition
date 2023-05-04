// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20 } from "src/base/ERC20.sol";
import { PriceOps } from "src/PricingOperations/PriceOps.sol";
import { Math } from "src/utils/Math.sol";

abstract contract Extension {
    error Extension__OnlyPriceOps();
    // Only callable by priceops.
    modifier onlyPriceOps() {
        if (msg.sender != address(priceOps)) revert Extension__OnlyPriceOps();
        _;
    }

    PriceOps public immutable priceOps;

    constructor(PriceOps _priceOps) {
        priceOps = _priceOps;
    }

    function setupSource(address asset, uint64 sourceId, bytes memory sourceData) external virtual;

    function getPriceInBase(uint64 sourceId) external view virtual returns (uint256, uint256, uint8);
}
