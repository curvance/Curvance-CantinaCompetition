// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseChildCVE } from "../TestBaseChildCVE.sol";
import { CVE } from "contracts/token/CVE.sol";

contract registerWormholeChainIDsTest is TestBaseChildCVE {
    uint256[] public chainIDs;
    uint16[] public wormholeChainIDs;

    function setUp() public override {
        super.setUp();

        chainIDs.push(1);
        wormholeChainIDs.push(2);
        chainIDs.push(42161);
        wormholeChainIDs.push(23);
        chainIDs.push(43114);
        wormholeChainIDs.push(6);
    }

    function test_registerWormholeChainIDs_fail_whenUnauthorized() public {
        vm.prank(address(0));

        vm.expectRevert(CVE.CVE__Unauthorized.selector);
        childCVE.registerWormholeChainIDs(chainIDs, wormholeChainIDs);
    }

    function test_registerWormholeChainIDs_success() public {
        childCVE.registerWormholeChainIDs(chainIDs, wormholeChainIDs);

        for (uint256 i = 0; i < chainIDs.length; i++) {
            assertEq(
                childCVE.wormholeChainId(chainIDs[i]),
                wormholeChainIDs[i]
            );
        }
    }
}
