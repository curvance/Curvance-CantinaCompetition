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
            centralRegistry.sequencer() == address(0),
            "CENTRAL_REGISTRY DEPLOY FAILED: CentralRegistry.sequencer == address(0) failed"
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
            cve.builderAddress() == address(this),
            "CVE DEPLOY FAILED: cve.builderAddress() == address(this) failed"
        );
        assertWithMsg(
            cve.daoTreasuryAllocation() == 60900010 ether,
            "CVE DEPLOY FAILED: CVE.daoTreasuryAllocation == 60900010 ether failed"
        );
        assertWithMsg(
            cve.builderAllocationPerMonth() > 0,
            "CVE DEPLOY FAILED: CVE.builderAllocationPerMonth() > 0 failed"
        );
    }

    /// @custom:property curv-16 The Market Manager’s gauge pool is set up correctly.
    function MarketManager_is_deployed() public {
        assertWithMsg(
            address(marketManager.gaugePool()) == address(gaugePool),
            "MarketManager DEPLOY FAILED: marketManager.gaugePool() == gaugePool failed"
        );
    }
}
