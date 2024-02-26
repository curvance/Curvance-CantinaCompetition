// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { DToken, ICentralRegistry } from "contracts/market/collateral/DToken.sol";
import { BlastYieldDelegable } from "contracts/libraries/BlastYieldDelegable.sol";

contract BlastDToken is DToken, BlastYieldDelegable {

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_,
        address underlying_,
        address marketManager_,
        address interestRateModel_
    ) DToken(
        centralRegistry_,
        underlying_,
        marketManager_,
        interestRateModel_
    ) BlastYieldDelegable (centralRegistry_) {}

}
