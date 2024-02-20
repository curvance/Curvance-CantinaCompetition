// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { CentralRegistry } from "contracts/architecture/CentralRegistry.sol";

contract SetGelatoSponsorTest is TestBaseMarket {
    event GelatoSponsorSet(address newAddress);

    address public newGelatoSponsor = makeAddr("Gelato Sponsor");

    function test_setGelatoSponsor_fail_whenUnauthorized() public {
        vm.prank(address(0));

        vm.expectRevert(
            CentralRegistry.CentralRegistry__Unauthorized.selector
        );
        centralRegistry.setGelatoSponsor(newGelatoSponsor);
    }

    function test_setGelatoSponsor_success() public {
        assertEq(centralRegistry.gelatoSponsor(), address(1));

        vm.expectEmit(true, true, true, true);
        emit GelatoSponsorSet(newGelatoSponsor);

        centralRegistry.setGelatoSponsor(newGelatoSponsor);

        assertEq(centralRegistry.gelatoSponsor(), newGelatoSponsor);
    }
}
