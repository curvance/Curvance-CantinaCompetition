// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseLendtroller } from "../TestBaseLendtroller.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract SetSeizePausedTest is TestBaseLendtroller {
    event ActionPaused(string action, bool pauseState);

    function test_setSeizePaused_fail_whenCallerIsNotAuthorized() public {
        vm.prank(address(1));

        vm.expectRevert(Lendtroller.Lendtroller__Unauthorized.selector);
        lendtroller.setSeizePaused(true);
    }

    function test_setSeizePaused_success() public {
        vm.expectRevert(Lendtroller.Lendtroller__TokenNotListed.selector);
        lendtroller.canSeize(address(cBALRETH), address(dUSDC));

        lendtroller.listToken(address(cBALRETH));
        lendtroller.listToken(address(dUSDC));

        lendtroller.canSeize(address(cBALRETH), address(dUSDC));

        assertEq(lendtroller.seizePaused(), 1);

        vm.expectEmit(true, true, true, true, address(lendtroller));
        emit ActionPaused("Seize Paused", true);

        lendtroller.setSeizePaused(true);

        vm.expectRevert(Lendtroller.Lendtroller__Paused.selector);
        lendtroller.canSeize(address(cBALRETH), address(dUSDC));

        assertEq(lendtroller.seizePaused(), 2);

        vm.expectEmit(true, true, true, true, address(lendtroller));
        emit ActionPaused("Seize Paused", false);

        lendtroller.setSeizePaused(false);

        assertEq(lendtroller.seizePaused(), 1);

        Lendtroller newLendtroller = new Lendtroller(
            ICentralRegistry(address(centralRegistry)),
            address(gaugePool)
        );

        centralRegistry.addLendingMarket(address(newLendtroller), 0);
        cBALRETH.setLendtroller(address(newLendtroller));

        vm.expectRevert(Lendtroller.Lendtroller__LendtrollerMismatch.selector);
        lendtroller.canSeize(address(cBALRETH), address(dUSDC));
    }
}
