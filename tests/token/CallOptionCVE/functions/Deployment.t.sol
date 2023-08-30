// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseCallOptionCVE } from "../TestBaseCallOptionCVE.sol";
import { CallOptionCVE } from "contracts/token/CallOptionCVE.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract CallOptionCVEDeploymentTest is TestBaseCallOptionCVE {
    function test_callOptionCVEDeployment_fail_whenCentralRegistryIsInvalid()
        public
    {
        vm.expectRevert("CallOptionCVE: invalid central registry");
        new CallOptionCVE(ICentralRegistry(address(0)), _USDC_ADDRESS);
    }

    function test_callOptionCVEDeployment_fail_whenPaymentTokenIsInvalid()
        public
    {
        vm.expectRevert("CallOptionCVE: invalid payment token");
        new CallOptionCVE(
            ICentralRegistry(address(centralRegistry)),
            address(0)
        );
    }

    function test_callOptionCVEDeployment_success() public {
        callOptionCVE = new CallOptionCVE(
            ICentralRegistry(address(centralRegistry)),
            _USDC_ADDRESS
        );

        assertEq(
            callOptionCVE.name(),
            string(abi.encodePacked(bytes32("CVE Options")))
        );
        assertEq(
            callOptionCVE.symbol(),
            string(abi.encodePacked(bytes32("optCVE")))
        );
        assertEq(
            address(callOptionCVE.centralRegistry()),
            address(centralRegistry)
        );
        assertEq(callOptionCVE.paymentToken(), _USDC_ADDRESS);
        assertEq(address(callOptionCVE.cve()), address(centralRegistry.CVE()));
        assertEq(callOptionCVE.totalSupply(), 7560001.242 ether);
    }
}
