// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseLendtroller } from "../TestBaseLendtroller.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";
import { IMToken } from "contracts/interfaces/market/IMToken.sol";

contract CanMintTest is TestBaseLendtroller {
    function test_canMint_fail_whenMintPaused() public {
        lendtroller.listToken(address(dUSDC));

        lendtroller.setMintPaused(IMToken(address(dUSDC)), true);
        vm.expectRevert(Lendtroller.Lendtroller__Paused.selector);
        lendtroller.canMint(address(dUSDC));
    }

    function test_canMint_fail_whenTokenNotListed() public {
        vm.expectRevert(Lendtroller.Lendtroller__TokenNotListed.selector);
        lendtroller.canMint(address(dUSDC));
    }

    function test_canMint_success() public {
        lendtroller.listToken(address(dUSDC));
        lendtroller.canMint(address(dUSDC));
    }
}
