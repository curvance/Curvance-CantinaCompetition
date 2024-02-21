// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { CentralRegistry } from "contracts/architecture/CentralRegistry.sol";

contract SetProtocolCompoundFeeTest is TestBaseMarket {
    function test_setProtocolCompoundFee_fail_whenUnauthorized() public {
        vm.prank(address(0));

        vm.expectRevert(
            CentralRegistry.CentralRegistry__Unauthorized.selector
        );
        centralRegistry.setProtocolCompoundFee(100);
    }

    function test_setProtocolCompoundFee_fail_whenParametersMisconfigured()
        public
    {
        vm.expectRevert(
            CentralRegistry.CentralRegistry__ParametersMisconfigured.selector
        );
        centralRegistry.setProtocolCompoundFee(501);

        centralRegistry.setProtocolCompoundFee(500);
    }

    function test_setProtocolCompoundFee_success() public {
        centralRegistry.setProtocolCompoundFee(100);
        assertEq(centralRegistry.protocolCompoundFee(), 100 * 1e14);
        uint256 newProtocolHarvestFee = centralRegistry.protocolYieldFee() +
            (100 * 1e14);
        assertEq(centralRegistry.protocolHarvestFee(), newProtocolHarvestFee);
    }
}
