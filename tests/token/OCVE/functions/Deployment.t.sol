// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseOCVE } from "../TestBaseOCVE.sol";
import { OCVE } from "contracts/token/OCVE.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract OCVEDeploymentTest is TestBaseOCVE {
    function test_oCVEDeployment_fail_whenCentralRegistryIsInvalid()
        public
    {
        vm.expectRevert(OCVE.OCVE__ParametersareInvalid.selector);
        new OCVE(ICentralRegistry(address(0)), _USDC_ADDRESS);
    }

    function test_oCVEDeployment_fail_whenPaymentTokenIsInvalid()
        public
    {
        vm.expectRevert(OCVE.OCVE__ParametersareInvalid.selector);
        new OCVE(
            ICentralRegistry(address(centralRegistry)),
            address(0)
        );
    }

    function test_oCVEDeployment_success() public {
        oCVE = new OCVE(
            ICentralRegistry(address(centralRegistry)),
            _USDC_ADDRESS
        );

        assertEq(
            oCVE.name(),
            string(abi.encodePacked(bytes32("CVE Options")))
        );
        assertEq(
            oCVE.symbol(),
            string(abi.encodePacked(bytes32("oCVE")))
        );
        assertEq(
            address(oCVE.centralRegistry()),
            address(centralRegistry)
        );
        assertEq(oCVE.paymentToken(), _USDC_ADDRESS);
        assertEq(address(oCVE.cve()), address(centralRegistry.CVE()));
        assertEq(oCVE.totalSupply(), 7560001.242 ether);
    }
}
