// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseOracleRouter } from "../TestBaseOracleRouter.sol";
import { OracleRouter } from "contracts/oracles/OracleRouter.sol";

contract ReplaceApprovedAdaptorTest is TestBaseOracleRouter {
    function test_replaceApprovedAdaptor_fail_whenCallerIsNotAuthorized() public {
        vm.prank(address(1));

        vm.expectRevert(OracleRouter.OracleRouter__Unauthorized.selector);
        oracleRouter.replaceApprovedAdaptor(address(chainlinkAdaptor));
    }

    function test_replaceApprovedAdaptor_fail_whenAdaptorsAreIdentical()
        public
    {
        oracleRouter.addApprovedAdaptor(address(chainlinkAdaptor));

        vm.expectRevert(OracleRouter.OracleRouter__InvalidParameter.selector);
        oracleRouter.replaceApprovedAdaptor(address(chainlinkAdaptor), address(chainlinkAdaptor));
    }

    function test_replaceApprovedAdaptor_fail_whenNewAdaptorIsAlreadyConfigured()
        public
    {
        oracleRouter.addApprovedAdaptor(address(chainlinkAdaptor));
        oracleRouter.addApprovedAdaptor(address(dualChainlinkAdaptor));

        vm.expectRevert(OracleRouter.OracleRouter__InvalidParameter.selector);
        oracleRouter.replaceApprovedAdaptor(address(dualChainlinkAdaptor), address(chainlinkAdaptor));
    }

    function test_replaceApprovedAdaptor_fail_whenCurrentAdaptorIsNotConfigured()
        public
    {
        oracleRouter.addApprovedAdaptor(address(chainlinkAdaptor));

        vm.expectRevert(OracleRouter.OracleRouter__InvalidParameter.selector);
        oracleRouter.replaceApprovedAdaptor(address(dualChainlinkAdaptor), address(chainlinkAdaptor));
    }

    function test_replaceApprovedAdaptor_success() public {
        oracleRouter.addApprovedAdaptor(address(chainlinkAdaptor));
        assertTrue(oracleRouter.isApprovedAdaptor(address(chainlinkAdaptor)));

        oracleRouter.replaceApprovedAdaptor(address(chainlinkAdaptor), address(dualChainlinkAdaptor));

        assertFalse(oracleRouter.isApprovedAdaptor(address(chainlinkAdaptor)));
        assertTrue(oracleRouter.isApprovedAdaptor(address(dualChainlinkAdaptor)));
    }
}
