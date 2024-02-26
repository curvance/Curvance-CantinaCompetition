// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { FeeAccumulator, ICentralRegistry } from "contracts/architecture/FeeAccumulator.sol";
import { BlastYieldDelegable } from "contracts/libraries/BlastYieldDelegable.sol";

contract BlastFeeAccumulator is FeeAccumulator, BlastYieldDelegable {

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        address oneBalanceFeeManager_
    ) FeeAccumulator(
        centralRegistry_,
        oneBalanceFeeManager_
    ) BlastYieldDelegable (centralRegistry_) {}

}
