// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseDToken } from "../TestBaseDToken.sol";
import { GaugeErrors } from "contracts/gauge/GaugeErrors.sol";

contract DTokenDepositReservesTest is TestBaseDToken {
    function test_dTokenDepositReserves_fail_whenCallIsNotAuthorized() public {
        vm.prank(address(1));

        vm.expectRevert("DToken: UNAUTHORIZED");
        dUSDC.depositReserves(100e6);
    }

    function test_dTokenDepositReserves_fail_whenAmountIsZero() public {
        vm.expectRevert(GaugeErrors.InvalidAmount.selector);
        dUSDC.depositReserves(0);
    }

    function test_dTokenDepositReserves_success() public {
        uint256 underlyingBalance = usdc.balanceOf(address(this));
        uint256 balance = dUSDC.balanceOf(address(this));
        uint256 totalSupply = dUSDC.totalSupply();

        dUSDC.depositReserves(100e6);

        assertEq(usdc.balanceOf(address(this)), underlyingBalance - 100e6);
        assertEq(dUSDC.balanceOf(address(this)), balance);
        assertEq(dUSDC.totalSupply(), totalSupply);
    }
}
