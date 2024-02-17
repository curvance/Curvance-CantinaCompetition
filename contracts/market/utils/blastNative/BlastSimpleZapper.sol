// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { SimpleZapper, ICentralRegistry } from "contracts/market/utils/SimpleZapper.sol";
import { BlastYieldDelegable } from "contracts/libraries/BlastYieldDelegable.sol";

contract BlastSimpleZapper is SimpleZapper, BlastYieldDelegable {

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        address marketManager_,
        address WETH_
    ) SimpleZapper(
        centralRegistry_,
        marketManager_,
        WETH_
    ) BlastYieldDelegable (centralRegistry_) {}

}
