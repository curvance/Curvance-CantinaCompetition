// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { BorrowZapper, ICentralRegistry } from "contracts/market/utils/BorrowZapper.sol";
import { BlastYieldDelegable } from "contracts/libraries/BlastYieldDelegable.sol";

contract BlastBorrowZapper is BorrowZapper, BlastYieldDelegable {

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_
    ) BorrowZapper(
        centralRegistry_
    ) BlastYieldDelegable (centralRegistry_) {}

}
