// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseLendtroller } from "../TestBaseLendtroller.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";

contract SetCloseFactorTest is TestBaseLendtroller {
    event NewCloseFactor(uint256 oldCloseFactor, uint256 newCloseFactor);

    function test_setCloseFactor_fail_whenCallerIsNotAuthorized() public {
        vm.prank(address(1));

        vm.expectRevert(Lendtroller.Lendtroller__Unauthorized.selector);
        lendtroller.setCloseFactor(1e4);
    }

    function test_setCloseFactor_fail_whenNewValueExceedsMaximum() public {
        vm.expectRevert(Lendtroller.Lendtroller__InvalidParameter.selector);
        lendtroller.setCloseFactor(1e4 + 1);
    }

    function test_setCloseFactor_success() public {
        vm.expectEmit(true, true, true, true, address(lendtroller));
        emit NewCloseFactor(0.5e18, 1e18);

        lendtroller.setCloseFactor(1e4);

        assertEq(lendtroller.closeFactor(), 1e18);
    }
}
