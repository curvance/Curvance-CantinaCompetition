// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseLendtroller } from "../TestBaseLendtroller.sol";

contract SetLiquidationIncentiveTest is TestBaseLendtroller {
    event NewLiquidationIncentive(
        uint256 oldLiquidationIncentiveScaled,
        uint256 newLiquidationIncentiveScaled
    );

    function test_setLiquidationIncentive_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.prank(address(1));

        vm.expectRevert("Lendtroller: UNAUTHORIZED");
        lendtroller.setLiquidationIncentive(1e18);
    }

    function test_setLiquidationIncentive_success() public {
        vm.expectEmit(true, true, true, true, address(lendtroller));
        emit NewLiquidationIncentive(0, 1e18);

        lendtroller.setLiquidationIncentive(1e18);

        assertEq(lendtroller.liquidationIncentiveScaled(), 1e18);
    }
}
