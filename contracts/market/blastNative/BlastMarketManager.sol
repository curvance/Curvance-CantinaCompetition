// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { MarketManager, ICentralRegistry } from "contracts/market/MarketManager.sol";
import { BlastYieldDelegable } from "contracts/libraries/BlastYieldDelegable.sol";

contract BlastMarketManager is MarketManager, BlastYieldDelegable {

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        address gaugePool_
    ) MarketManager(
        centralRegistry_,
        gaugePool_
    ) BlastYieldDelegable (centralRegistry_) {}

}
