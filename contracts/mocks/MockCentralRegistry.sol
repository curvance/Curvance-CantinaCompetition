// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import "contracts/architecture/CentralRegistry.sol";

contract MockCentralRegistry is CentralRegistry {
    constructor(
        address daoAddress_, 
        address timelock_, 
        address emergencyCouncil_, 
        uint256 genesisEpoch_
    ) CentralRegistry(daoAddress_, timelock_, emergencyCouncil_, genesisEpoch_) {}
}
