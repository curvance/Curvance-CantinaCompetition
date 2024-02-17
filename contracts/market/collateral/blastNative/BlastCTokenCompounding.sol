// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CTokenCompounding, ICentralRegistry } from "contracts/market/collateral/CTokenCompounding.sol";
import { BlastYieldDelegable } from "contracts/libraries/BlastYieldDelegable.sol";

contract BlastCTokenCompounding is CTokenCompounding, BlastYieldDelegable {

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        IERC20 asset_,
        address marketManager_
    ) CTokenCompounding(
        centralRegistry_,
        asset_,
        marketManager_
    ) BlastYieldDelegable (centralRegistry_) {}

}
