// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { CentralRegistry } from "contracts/architecture/CentralRegistry.sol";

contract RegisterCCTPDomainsTest is TestBaseMarket {
    uint256[] public chainIDs;
    uint32[] public cctpDomains;

    function setUp() public override {
        super.setUp();

        chainIDs.push(1);
        cctpDomains.push(0);
        chainIDs.push(42161);
        cctpDomains.push(3);
        chainIDs.push(43114);
        cctpDomains.push(1);
    }

    function test_registerCCTPDomains_fail_whenUnauthorized() public {
        vm.prank(address(0));

        vm.expectRevert(
            CentralRegistry.CentralRegistry__Unauthorized.selector
        );
        centralRegistry.registerCCTPDomains(chainIDs, cctpDomains);
    }

    function test_registerCCTPDomains_success() public {
        centralRegistry.registerCCTPDomains(chainIDs, cctpDomains);

        for (uint256 i = 0; i < chainIDs.length; i++) {
            assertEq(centralRegistry.cctpDomain(chainIDs[i]), cctpDomains[i]);
        }
    }
}
