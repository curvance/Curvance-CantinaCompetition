// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseOracleRouter } from "../TestBaseOracleRouter.sol";
import { OracleRouter } from "contracts/oracles/OracleRouter.sol";

contract SetChainlinkDelayTest is TestBaseOracleRouter {
    function test_setChainlinkDelay_fail_whenCallerIsNotAuthorized() public {
        vm.prank(address(1));

        vm.expectRevert(OracleRouter.OracleRouter__Unauthorized.selector);
        oracleRouter.setChainlinkDelay(0.5 days);
    }

    function test_setChainlinkDelay_fail_whenDelayIsTooLarge() public {
        vm.expectRevert(OracleRouter.OracleRouter__InvalidParameter.selector);
        oracleRouter.setChainlinkDelay(1 days + 1);
    }

    function test_setChainlinkDelay_success() public {
        assertEq(oracleRouter.CHAINLINK_MAX_DELAY(), 1 days);

        oracleRouter.setChainlinkDelay(0.5 days);

        assertEq(oracleRouter.CHAINLINK_MAX_DELAY(), 0.5 days);
    }
}
