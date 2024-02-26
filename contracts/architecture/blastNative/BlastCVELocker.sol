// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CVELocker, ICentralRegistry } from "contracts/architecture/CVELocker.sol";
import { BlastYieldDelegable } from "contracts/libraries/BlastYieldDelegable.sol";

contract BlastCVELocker is CVELocker, BlastYieldDelegable {

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_, 
        address rewardToken_
    ) CVELocker(centralRegistry_, rewardToken_) BlastYieldDelegable (centralRegistry_) {}

}
