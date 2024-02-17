// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ComplexZapper, ICentralRegistry } from "contracts/market/utils/ComplexZapper.sol";
import { BlastYieldDelegable } from "contracts/libraries/BlastYieldDelegable.sol";

contract BlastComplexZapper is ComplexZapper, BlastYieldDelegable {

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        address marketManager_,
        address WETH_
    ) ComplexZapper(
        centralRegistry_,
        marketManager_,
        WETH_
    ) BlastYieldDelegable (centralRegistry_) {}

}
