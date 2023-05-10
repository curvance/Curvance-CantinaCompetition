// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import "../utils/CentralRegistry.sol";

contract MockCentralRegistry is CentralRegistry {
    constructor(address dao_, uint256 genesisEpoch_) CentralRegistry(dao_, genesisEpoch_) {}
}
