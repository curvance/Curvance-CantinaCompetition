// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseLendtroller } from "../TestBaseLendtroller.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";
import { IMToken } from "contracts/interfaces/market/IMToken.sol";

contract SetMintPausedTest is TestBaseLendtroller {
    event ActionPaused(IMToken mToken, string action, bool pauseState);

    function test_setMintPaused_fail_whenCallerIsNotAuthorized() public {
        vm.prank(address(1));

        vm.expectRevert(Lendtroller.Lendtroller__Unauthorized.selector);
        lendtroller.setMintPaused(IMToken(address(dUSDC)), true);
    }

    function test_setMintPaused_fail_whenMTokenIsNotListed() public {
        vm.expectRevert(Lendtroller.Lendtroller__TokenNotListed.selector);
        lendtroller.canMint(address(dUSDC));

        vm.expectRevert(Lendtroller.Lendtroller__TokenNotListed.selector);
        lendtroller.setMintPaused(IMToken(address(dUSDC)), true);
    }

    function test_setMintPaused_success() public {
        lendtroller.listToken(address(dUSDC));

        lendtroller.canMint(address(dUSDC));

        assertEq(lendtroller.mintPaused(address(dUSDC)), 0);

        vm.expectEmit(true, true, true, true, address(lendtroller));
        emit ActionPaused(IMToken(address(dUSDC)), "Mint Paused", true);

        lendtroller.setMintPaused(IMToken(address(dUSDC)), true);

        vm.expectRevert(Lendtroller.Lendtroller__Paused.selector);
        lendtroller.canMint(address(dUSDC));

        assertEq(lendtroller.mintPaused(address(dUSDC)), 2);

        vm.expectEmit(true, true, true, true, address(lendtroller));
        emit ActionPaused(IMToken(address(dUSDC)), "Mint Paused", false);

        lendtroller.setMintPaused(IMToken(address(dUSDC)), false);

        assertEq(lendtroller.mintPaused(address(dUSDC)), 1);
    }
}
