// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { SimpleRewardZapper, ICentralRegistry } from "contracts/architecture/utils/SimpleRewardZapper.sol";
import { BlastYieldDelegable } from "contracts/libraries/BlastYieldDelegable.sol";

contract BlastSimpleRewardZapper is SimpleRewardZapper, BlastYieldDelegable {

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        address WETH_
    ) SimpleRewardZapper(
        centralRegistry_,
        WETH_
    ) BlastYieldDelegable (centralRegistry_) {}

}
