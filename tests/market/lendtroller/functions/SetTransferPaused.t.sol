// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseLendtroller } from "../TestBaseLendtroller.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";

contract SetTransferPausedTest is TestBaseLendtroller {
    event ActionPaused(string action, bool pauseState);

    function test_setTransferPaused_fail_whenCallerIsNotAuthorized() public {
        vm.prank(address(1));

        vm.expectRevert(Lendtroller.Lendtroller__Unauthorized.selector);
        lendtroller.setTransferPaused(true);
    }

    function test_setTransferPaused_success() public {
        lendtroller.listMarketToken(address(dUSDC));

        lendtroller.canTransfer(address(dUSDC), address(this), 1);

        assertEq(lendtroller.transferPaused(), 1);

        vm.expectEmit(true, true, true, true, address(lendtroller));
        emit ActionPaused("Transfer Paused", true);

        lendtroller.setTransferPaused(true);

        vm.expectRevert(Lendtroller.Lendtroller__Paused.selector);
        lendtroller.canTransfer(address(dUSDC), address(this), 1);

        assertEq(lendtroller.transferPaused(), 2);

        vm.expectEmit(true, true, true, true, address(lendtroller));
        emit ActionPaused("Transfer Paused", false);

        lendtroller.setTransferPaused(false);

        assertEq(lendtroller.transferPaused(), 1);
    }
}
