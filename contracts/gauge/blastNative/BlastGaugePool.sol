// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { GaugePool, ICentralRegistry } from "contracts/gauge/GaugePool.sol";
import { BlastYieldDelegable } from "contracts/libraries/BlastYieldDelegable.sol";

contract BlastGaugePool is GaugePool, BlastYieldDelegable {

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_
    ) GaugePool(
        centralRegistry_
    ) BlastYieldDelegable (centralRegistry_) {}

}
