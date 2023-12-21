// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseLendtroller } from "../TestBaseLendtroller.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract CanSeizeTest is TestBaseLendtroller {
    function test_canSeize_fail_whenPaused() public {
        lendtroller.setSeizePaused(true);

        vm.expectRevert(Lendtroller.Lendtroller__Paused.selector);
        lendtroller.canSeize(address(cBALRETH), address(dUSDC));
    }

    function test_canSeize_fail_whenCTokenNotListed() public {
        vm.expectRevert(Lendtroller.Lendtroller__TokenNotListed.selector);
        lendtroller.canSeize(address(cBALRETH), address(dUSDC));
    }

    function test_canSeize_fail_whenDTokenNotListed() public {
        lendtroller.listToken(address(cBALRETH));

        vm.expectRevert(Lendtroller.Lendtroller__TokenNotListed.selector);
        lendtroller.canSeize(address(cBALRETH), address(dUSDC));
    }

    function test_canSeize_success() public {
        lendtroller.listToken(address(cBALRETH));
        lendtroller.listToken(address(dUSDC));

        lendtroller.canSeize(address(cBALRETH), address(dUSDC));
    }

    // function test_canSeize_fail_whenLendtrollersMismatch() public {
    //     lendtroller.listToken(address(cBALRETH));
    //     lendtroller.listToken(address(dUSDC));

    //     Lendtroller newLendtroller = new Lendtroller(
    //         ICentralRegistry(address(centralRegistry)),
    //         address(gaugePool)
    //     );
    //     centralRegistry.addLendingMarket(address(newLendtroller), 1000);
    //     dUSDC.setLendtroller(address(newLendtroller));

    //     vm.expectRevert(Lendtroller.Lendtroller__LendtrollerMismatch.selector);
    //     lendtroller.canSeize(address(cBALRETH), address(dUSDC));
    // }
}
