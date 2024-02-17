// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { VeCVE, ICentralRegistry } from "contracts/token/ChildVeCVE.sol";
import { BlastYieldDelegable } from "contracts/libraries/BlastYieldDelegable.sol";

contract BlastVeCVE is VeCVE, BlastYieldDelegable {

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_
    ) VeCVE(centralRegistry_) BlastYieldDelegable (centralRegistry_) {}

}
