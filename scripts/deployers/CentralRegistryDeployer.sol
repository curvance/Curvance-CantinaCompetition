// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { CentralRegistry } from "contracts/architecture/CentralRegistry.sol";

contract CentralRegistryDeployer is Script {
    address centralRegistry;

    function deployCentralRegistry(
        address daoAddress,
        address timelock,
        address emergencyCouncil,
        uint256 genesisEpoch,
        address sequencer
    ) internal {
        require(daoAddress != address(0), "Set the daoAddress!");
        require(timelock != address(0), "Set the timelock!");
        require(emergencyCouncil != address(0), "Set the emergencyCouncil!");
        require(sequencer != address(0), "Set the sequencer!");

        centralRegistry = address(
            new CentralRegistry(
                daoAddress,
                timelock,
                emergencyCouncil,
                genesisEpoch,
                sequencer
            )
        );

        console.log("centralRegistry: ", centralRegistry);
    }

    function transferEmergencyCouncil(address newEmergencyCouncil) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");

        CentralRegistry(centralRegistry).transferEmergencyCouncil(
            newEmergencyCouncil
        );
        console.log("transferEmergencyCouncil: ", newEmergencyCouncil);
    }

    function setLockBoostMultiplier(uint256 lockBoostMultiplier) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");

        CentralRegistry(centralRegistry).setLockBoostMultiplier(
            lockBoostMultiplier
        );
        console.log("setLockBoostMultiplier: ", lockBoostMultiplier);
    }

    function addHarvester(address harvester) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");
        require(harvester != address(0), "Set the harvester!");

        CentralRegistry(centralRegistry).addHarvester(harvester);
        console.log("addHarvester: ", harvester);
    }

    function setCVE(address cve) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");
        require(cve != address(0), "Set the cve!");

        CentralRegistry(centralRegistry).setCVE(cve);
        console.log("setCVE: ", cve);
    }

    function setCVELocker(address cveLocker) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");
        require(cveLocker != address(0), "Set the cveLocker!");

        CentralRegistry(centralRegistry).setCVELocker(cveLocker);
        console.log("setCVELocker: ", cveLocker);
    }

    function setProtocolMessagingHub(address protocolMessagingHub) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");
        require(
            protocolMessagingHub != address(0),
            "Set the protocolMessagingHub!"
        );

        CentralRegistry(centralRegistry).setProtocolMessagingHub(
            protocolMessagingHub
        );
        console.log("setProtocolMessagingHub: ", protocolMessagingHub);
    }

    function setFeeAccumulator(address feeAccumulator) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");
        require(feeAccumulator != address(0), "Set the feeAccumulator!");

        CentralRegistry(centralRegistry).setFeeAccumulator(feeAccumulator);
        console.log("setFeeAccumulator: ", feeAccumulator);
    }

    function setVeCVE(address veCve) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");
        require(veCve != address(0), "Set the veCve!");

        CentralRegistry(centralRegistry).setVeCVE(veCve);
        console.log("setVeCVE: ", veCve);
    }

    function setVoteBoostMultiplier(uint256 voteBoostMultiplier) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");

        CentralRegistry(centralRegistry).setVoteBoostMultiplier(
            voteBoostMultiplier
        );
        console.log("setVoteBoostMultiplier: ", voteBoostMultiplier);
    }
}
