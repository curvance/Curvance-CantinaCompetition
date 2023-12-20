// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;
import { StatefulBaseMarket } from "tests/fuzzing/StatefulBaseMarket.sol";

contract TestStatefulDeployments is StatefulBaseMarket {
    function CentralRegistry_is_deployed_and_setup() public {
        assertWithMsg(
            centralRegistry.daoAddress() == address(this),
            "CENTRAL_REGISTRY DEPLOY FAILED: CentralRegistry.daoAddress == address(this) failed"
        );
        assertWithMsg(
            centralRegistry.timelock() == address(this),
            "CENTRAL_REGISTRY DEPLOY FAILED: CentralRegistry.timelock() == address(this) failed"
        );
        assertWithMsg(
            centralRegistry.emergencyCouncil() == address(this),
            "CENTRAL_REGISTRY DEPLOY FAILED: CentralRegistry.emergencyCouncil() == address(this) failed"
        );
        assertWithMsg(
            centralRegistry.genesisEpoch() == 0,
            "CENTRAL_REGISTRY DEPLOY FAILED: CentralRegistry.genesisEpoch() == 0 failed"
        );
        assertWithMsg(
            centralRegistry.sequencer() == address(this),
            "CENTRAL_REGISTRY DEPLOY FAILED: CentralRegistry.sequencer == address(this) failed"
        );
        assertWithMsg(
            centralRegistry.hasDaoPermissions(address(this)),
            "CENTRAL_REGISTRY DEPLOY FAILED: CentralRegistry.hasDaoPermissions[address(this)] failed"
        );
        assertWithMsg(
            centralRegistry.hasElevatedPermissions(address(this)),
            "CENTRAL_REGISTRY DEPLOY FAILED: CentralRegistry.hasElevatedPermissinos(address(this)) failed"
        );
    }

    function CentralRegistry_is_setup() public {
        assertWithMsg(
            address(centralRegistry.cve()) == address(cve),
            "CVE SETUP FAILED: CentralRegistry.cve() == cve failed"
        );
        assertWithMsg(
            address(centralRegistry.veCVE()) == address(veCVE),
            "CVE SETUP FAILED: CentralRegistry.veCVE() == vecve failed"
        );
        assertWithMsg(
            address(centralRegistry.cveLocker()) == address(cveLocker),
            "CVE SETUP FAILED: CentralRegistry.cveLocker != cveLocker"
        );
        assertWithMsg(
            address(centralRegistry.protocolMessagingHub()) ==
                address(protocolMessagingHub),
            "CVE SETUP FAILED: CentralRegistry.protocolMessagingHub == protocolMessagingHub"
        );
    }

    function CVE_is_deployed() public {
        assertWithMsg(
            address(cve.centralRegistry()) == address(centralRegistry),
            "CVE DEPLOY FAILED: CVE.centralRegistry == centralRegistry failed"
        );
        assertWithMsg(
            cve.teamAddress() == address(this),
            "CVE DEPLOY FAILED: cve.teamAddress() == address(this) failed"
        );
        assertWithMsg(
            cve.daoTreasuryAllocation() == 10000 ether,
            "CVE DEPLOY FAILED: CVE.daoTreasuryAllocation == 10000 ether failed"
        );
        assertWithMsg(
            cve.teamAllocationPerMonth() > 0,
            "CVE DEPLOY FAILED: CVE.teamAllocationperMonth() == 10000 ether/48 failed"
        );
    }
}
