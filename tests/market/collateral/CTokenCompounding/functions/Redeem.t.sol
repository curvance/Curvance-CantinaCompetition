// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseCTokenCompounding } from "../TestBaseCTokenCompounding.sol";
import { CTokenCompounding } from "contracts/market/collateral/CTokenCompounding.sol";
import { GaugeErrors } from "contracts/gauge/GaugeErrors.sol";

contract CTokenCompounding_RedeemTest is TestBaseCTokenCompounding {
    event Transfer(address indexed from, address indexed to, uint256 amount);

    function test_CTokenCompounding_Redeem_fail_whenNoEnoughToRedeem() public {
        address owner = address(1);
        vm.prank(owner);

        vm.expectRevert();
        cBALRETH.redeem(100, owner, owner);
    }

    function test_CTokenCompounding_Redeem_fail_whenAmountIsZero() public {
        cBALRETH.mint(100, address(this));

        vm.expectRevert(CTokenCompounding.CTokenCompounding__ZeroAssets.selector);
        cBALRETH.redeem(0, address(this), address(this));
    }

    function test_CTokenCompounding_Redeem_success() public {
        cBALRETH.mint(100, address(this));

        uint256 underlyingBalance = balRETH.balanceOf(address(this));
        uint256 balance = cBALRETH.balanceOf(address(this));
        uint256 totalSupply = cBALRETH.totalSupply();

        vm.expectEmit(true, true, true, true, address(cBALRETH));
        emit Transfer(address(this), address(0), 100);

        cBALRETH.redeem(100, address(this), address(this));

        assertEq(balRETH.balanceOf(address(this)), underlyingBalance + 100);
        assertEq(cBALRETH.balanceOf(address(this)), balance - 100);
        assertEq(cBALRETH.totalSupply(), totalSupply - 100);
    }
}
