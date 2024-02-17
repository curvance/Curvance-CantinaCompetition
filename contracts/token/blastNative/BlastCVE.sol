// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CVE, ICentralRegistry } from "contracts/token/ChildCVE.sol";
import { BlastYieldDelegable } from "contracts/libraries/BlastYieldDelegable.sol";

contract BlastCVE is CVE, BlastYieldDelegable {

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_
    ) CVE(centralRegistry_) BlastYieldDelegable (centralRegistry_) {}

}
