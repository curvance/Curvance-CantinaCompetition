// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import "contracts/architecture/CentralRegistry.sol";

contract MockCentralRegistry is CentralRegistry {
    constructor(
        address daoAddress_,
        address timelock_,
        address emergencyCouncil_,
        uint256 genesisEpoch_,
        address sequencer_,
        address feeToken_
    )
        CentralRegistry(
            daoAddress_,
            timelock_,
            emergencyCouncil_,
            genesisEpoch_,
            sequencer_,
            feeToken_
        )
    {}
}
