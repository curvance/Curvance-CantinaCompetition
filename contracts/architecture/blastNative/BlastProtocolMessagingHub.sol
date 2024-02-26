// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ProtocolMessagingHub, ICentralRegistry } from "contracts/architecture/ProtocolMessagingHub.sol";
import { BlastYieldDelegable } from "contracts/libraries/BlastYieldDelegable.sol";

contract BlastProtocolMessagingHub is ProtocolMessagingHub, BlastYieldDelegable {

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_
    ) ProtocolMessagingHub(
        centralRegistry_
    ) BlastYieldDelegable (centralRegistry_) {}

}
