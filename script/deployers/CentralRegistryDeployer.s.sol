// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { CentralRegistry } from "contracts/architecture/CentralRegistry.sol";

contract CentralRegistryDeployer is Script {
    address centralRegistry;

    function _deployCentralRegistry(
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

    function _setLockBoostMultiplier(uint256 lockBoostMultiplier) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");

        CentralRegistry(centralRegistry).setLockBoostMultiplier(
            lockBoostMultiplier
        );
        console.log(
            "centralRegistry.setLockBoostMultiplier: ",
            lockBoostMultiplier
        );
    }

    function _addHarvester(address harvester) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");
        require(harvester != address(0), "Set the harvester!");

        CentralRegistry(centralRegistry).addHarvester(harvester);
        console.log("centralRegistry.addHarvester: ", harvester);
    }

    function _setCVE(address cve) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");
        require(cve != address(0), "Set the cve!");

        CentralRegistry(centralRegistry).setCVE(cve);
        console.log("centralRegistry.setCVE: ", cve);
    }

    function _setCVELocker(address cveLocker) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");
        require(cveLocker != address(0), "Set the cveLocker!");

        CentralRegistry(centralRegistry).setCVELocker(cveLocker);
        console.log("centralRegistry.setCVELocker: ", cveLocker);
    }

    function _setProtocolMessagingHub(address protocolMessagingHub) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");
        require(
            protocolMessagingHub != address(0),
            "Set the protocolMessagingHub!"
        );

        CentralRegistry(centralRegistry).setProtocolMessagingHub(
            protocolMessagingHub
        );
        console.log(
            "centralRegistry.setProtocolMessagingHub: ",
            protocolMessagingHub
        );
    }

    function _setFeeAccumulator(address feeAccumulator) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");
        require(feeAccumulator != address(0), "Set the feeAccumulator!");

        CentralRegistry(centralRegistry).setFeeAccumulator(feeAccumulator);
        console.log("centralRegistry.setFeeAccumulator: ", feeAccumulator);
    }

    function _setVeCVE(address veCve) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");
        require(veCve != address(0), "Set the veCve!");

        CentralRegistry(centralRegistry).setVeCVE(veCve);
        console.log("centralRegistry.setVeCVE: ", veCve);
    }

    function _setVoteBoostMultiplier(uint256 voteBoostMultiplier) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");

        CentralRegistry(centralRegistry).setVoteBoostMultiplier(
            voteBoostMultiplier
        );
        console.log(
            "centralRegistry.setVoteBoostMultiplier: ",
            voteBoostMultiplier
        );
    }

    function _addGaugeController(address gaugePool) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");
        require(gaugePool != address(0), "Set the gaugePool!");

        CentralRegistry(centralRegistry).addGaugeController(gaugePool);
        console.log("centralRegistry.addGaugeController: ", gaugePool);
    }

    function _addLendingMarket(
        address lendtroller,
        uint256 marketInterestFactor
    ) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");
        require(lendtroller != address(0), "Set the lendtroller!");

        CentralRegistry(centralRegistry).addLendingMarket(
            lendtroller,
            marketInterestFactor
        );
        console.log("centralRegistry.addLendingMarket: ", lendtroller);
    }

    function _addZapper(address zapper) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");
        require(zapper != address(0), "Set the zapper!");

        CentralRegistry(centralRegistry).addZapper(zapper);
        console.log("centralRegistry.addZapper: ", zapper);
    }

    function _transferDaoOwnership(address daoAddress) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");
        require(daoAddress != address(0), "Set the daoAddress!");

        CentralRegistry(centralRegistry).transferDaoOwnership(daoAddress);
        console.log("centralRegistry.transferDaoOwnership: ", daoAddress);
    }

    function _migrateTimelockConfiguration(address timelock) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");
        require(timelock != address(0), "Set the timelock!");

        CentralRegistry(centralRegistry).migrateTimelockConfiguration(
            timelock
        );
        console.log(
            "centralRegistry.migrateTimelockConfiguration: ",
            timelock
        );
    }

    function _transferEmergencyCouncil(address emergencyCouncil) internal {
        require(centralRegistry != address(0), "Set the centralRegistry!");
        require(emergencyCouncil != address(0), "Set the emergencyCouncil!");

        CentralRegistry(centralRegistry).transferEmergencyCouncil(
            emergencyCouncil
        );
        console.log(
            "centralRegistry.transferEmergencyCouncil: ",
            emergencyCouncil
        );
    }
}
