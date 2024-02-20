// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { CentralRegistry } from "contracts/architecture/CentralRegistry.sol";
import { DENOMINATOR } from "contracts/libraries/Constants.sol";

contract SetVoteBoostMultiplierTest is TestBaseMarket {
    function test_setVoteBoostMultiplier_fail_whenUnauthorized() public {
        vm.prank(address(0));

        vm.expectRevert(
            CentralRegistry.CentralRegistry__Unauthorized.selector
        );
        centralRegistry.setVoteBoostMultiplier(100);
    }

    function test_setVoteBoostMultiplier_fail_whenParametersMisconfigured()
        public
    {
        vm.expectRevert(
            CentralRegistry.CentralRegistry__ParametersMisconfigured.selector
        );
        centralRegistry.setVoteBoostMultiplier(DENOMINATOR - 1);

        centralRegistry.setVoteBoostMultiplier(0);
        centralRegistry.setVoteBoostMultiplier(DENOMINATOR);
    }

    function test_setVoteBoostMultiplier_success() public {
        centralRegistry.setVoteBoostMultiplier(11000);
        assertEq(centralRegistry.voteBoostMultiplier(), 11000);
    }
}
