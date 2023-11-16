// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { VeCVE } from "contracts/token/VeCVE.sol";
import { TestBaseVeCVE } from "../TestBaseVeCVE.sol";

contract VeCVEDeploymentTest is TestBaseVeCVE {
    function test_veCVEDeployment_fail_whenCentralRegistryIsInvalid() public {
        vm.expectRevert(VeCVE.VeCVE__ParametersAreInvalid.selector);
        new VeCVE(ICentralRegistry(address(1)), 0);
    }

    function test_veCVEDeployment_success() public {
        veCVE = new VeCVE(ICentralRegistry(address(centralRegistry)), 11000);

        assertEq(
            veCVE.name(),
            string(abi.encodePacked(bytes32("Vote Escrowed CVE")))
        );
        assertEq(veCVE.symbol(), string(abi.encodePacked(bytes32("VeCVE"))));
        assertEq(address(veCVE.centralRegistry()), address(centralRegistry));
        assertEq(veCVE.genesisEpoch(), centralRegistry.genesisEpoch());
        assertEq(veCVE.cve(), centralRegistry.CVE());
        assertEq(address(veCVE.cveLocker()), centralRegistry.cveLocker());
        assertEq(veCVE.clPointMultiplier(), 11000);
    }
}
