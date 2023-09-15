// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseDToken } from "../TestBaseDToken.sol";

contract DTokenRedeemUnderlyingTest is TestBaseDToken {
    event Transfer(address indexed from, address indexed to, uint256 amount);

    function test_dTokenRedeemUnderlying_fail_whenNoEnoughToRedeem() public {
        vm.prank(address(1));

        vm.expectRevert();
        dUSDC.redeemUnderlying(100e6);
    }

    function test_dTokenRedeemUnderlying_fail_whenAmountIsZero() public {
        dUSDC.mint(100e6);

        vm.expectRevert();
        dUSDC.redeemUnderlying(0);
    }

    function test_dTokenRedeemUnderlying_success() public {
        dUSDC.mint(100e6);

        uint256 underlyingBalance = usdc.balanceOf(address(this));
        uint256 balance = dUSDC.balanceOf(address(this));
        uint256 totalSupply = dUSDC.totalSupply();

        vm.expectEmit(true, true, true, true, address(dUSDC));
        emit Transfer(address(this), address(0), 100e6);

        dUSDC.redeemUnderlying(100e6);

        assertEq(usdc.balanceOf(address(this)), underlyingBalance + 100e6);
        assertEq(dUSDC.balanceOf(address(this)), balance - 100e6);
        assertEq(dUSDC.totalSupply(), totalSupply - 100e6);
    }
}
