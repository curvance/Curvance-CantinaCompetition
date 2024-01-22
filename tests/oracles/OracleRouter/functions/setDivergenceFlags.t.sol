// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseOracleRouter } from "../TestBaseOracleRouter.sol";
import { OracleRouter } from "contracts/oracles/OracleRouter.sol";

contract SetDivergenceFlagsTest is TestBaseOracleRouter {
    function test_setCautionDivergenceFlag_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.prank(address(1));

        vm.expectRevert(OracleRouter.OracleRouter__Unauthorized.selector);
        oracleRouter.setDivergenceFlags(10200, 10200);
    }

    function test_setCautionDivergenceFlag_fail_whenDivergenceIsTooSmall()
        public
    {
        vm.expectRevert(OracleRouter.OracleRouter__InvalidParameter.selector);
        oracleRouter.setDivergenceFlags(10199, 10200);
    }

    function test_setCautionDivergenceFlag_fail_whenDivergenceIsTooLarge()
        public
    {
        vm.expectRevert(OracleRouter.OracleRouter__InvalidParameter.selector);
        oracleRouter.setDivergenceFlags(12001, 10200);
    }

    function test_setCautionDivergenceFlag_success() public {
        assertEq(oracleRouter.cautionDivergenceFlag(), 10500);

        oracleRouter.setDivergenceFlags(10200, 11000);

        assertEq(oracleRouter.cautionDivergenceFlag(), 10200);
    }

    function test_setBadSourceDivergenceFlag_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.prank(address(1));

        vm.expectRevert(OracleRouter.OracleRouter__Unauthorized.selector);
        oracleRouter.setDivergenceFlags(10200, 10200);
    }

    function test_setBadSourceDivergenceFlag_fail_whenDivergenceIsTooSmall()
        public
    {
        vm.expectRevert(OracleRouter.OracleRouter__InvalidParameter.selector);
        oracleRouter.setDivergenceFlags(10200, 10199);
    }

    function test_setBadSourceDivergenceFlag_fail_whenDivergenceIsTooLarge()
        public
    {
        vm.expectRevert(OracleRouter.OracleRouter__InvalidParameter.selector);
        oracleRouter.setDivergenceFlags(10200, 12001);
    }

    function test_setBadSourceDivergenceFlag_success() public {
        assertEq(oracleRouter.badSourceDivergenceFlag(), 11000);

        oracleRouter.setDivergenceFlags(10500, 10800);

        assertEq(oracleRouter.badSourceDivergenceFlag(), 10800);
    }

    function test_setDivergenceFlags_fail_whenCautionEqualToBadSource()
        public
    {
        vm.expectRevert(OracleRouter.OracleRouter__InvalidParameter.selector);
        oracleRouter.setDivergenceFlags(10200, 10200);
    }

    function test_setDivergenceFlags_fail_whenCautionLargerThanBadSource()
        public
    {
        vm.expectRevert(OracleRouter.OracleRouter__InvalidParameter.selector);
        oracleRouter.setDivergenceFlags(10500, 10200);
    }

}
