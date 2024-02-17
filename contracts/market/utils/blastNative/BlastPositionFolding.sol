// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { PositionFolding, ICentralRegistry } from "contracts/market/utils/PositionFolding.sol";
import { BlastYieldDelegable } from "contracts/libraries/BlastYieldDelegable.sol";

contract BlastPositionFolding is PositionFolding, BlastYieldDelegable {

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        address marketManager_
    ) PositionFolding(
        centralRegistry_,
        marketManager_
    ) BlastYieldDelegable (centralRegistry_) {}

}
