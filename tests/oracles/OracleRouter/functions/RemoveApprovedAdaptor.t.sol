// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseOracleRouter } from "../TestBaseOracleRouter.sol";
import { OracleRouter } from "contracts/oracles/OracleRouter.sol";

contract RemoveApprovedAdaptorTest is TestBaseOracleRouter {
    function test_removeApprovedAdaptor_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.prank(address(1));

        vm.expectRevert(OracleRouter.OracleRouter__Unauthorized.selector);
        oracleRouter.removeApprovedAdaptor(address(chainlinkAdaptor));
    }

    function test_removeApprovedAdaptor_fail_whenAdaptorDoesNotExist() public {
        vm.expectRevert(OracleRouter.OracleRouter__InvalidParameter.selector);
        oracleRouter.removeApprovedAdaptor(address(chainlinkAdaptor));
    }

    function test_removeApprovedAdaptor_success() public {
        oracleRouter.addApprovedAdaptor(address(chainlinkAdaptor));

        assertTrue(oracleRouter.isApprovedAdaptor(address(chainlinkAdaptor)));

        oracleRouter.removeApprovedAdaptor(address(chainlinkAdaptor));

        assertFalse(oracleRouter.isApprovedAdaptor(address(chainlinkAdaptor)));
    }
}
