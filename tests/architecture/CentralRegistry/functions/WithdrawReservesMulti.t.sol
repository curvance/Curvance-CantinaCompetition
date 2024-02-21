// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { CentralRegistry } from "contracts/architecture/CentralRegistry.sol";

contract WithdrawReservesMultiTest is TestBaseMarket {
    address[] public dTokens;

    function setUp() public override {
        super.setUp();

        gaugePool.start(address(marketManager));

        dTokens.push(address(dUSDC));
        dTokens.push(address(dDAI));

        deal(_USDC_ADDRESS, address(this), 1000e6);
        deal(_DAI_ADDRESS, address(this), 1000e18);

        usdc.approve(address(dUSDC), 1000e6);
        dai.approve(address(dDAI), 1000e18);

        marketManager.listToken(address(dUSDC));
        marketManager.listToken(address(dDAI));

        dUSDC.depositReserves(100e6);
        dDAI.depositReserves(100e18);
    }

    function test_withdrawReservesMulti_fail_whenUnauthorized() public {
        vm.prank(address(0));

        vm.expectRevert(
            CentralRegistry.CentralRegistry__Unauthorized.selector
        );
        centralRegistry.withdrawReservesMulti(dTokens);
    }

    function test_withdrawReservesMulti_fail_whenDTokensLengthIsZero() public {
        dTokens.pop();
        dTokens.pop();

        vm.expectRevert(
            CentralRegistry.CentralRegistry__ParametersMisconfigured.selector
        );
        centralRegistry.withdrawReservesMulti(dTokens);
    }

    function test_withdrawReservesMulti_fail_whenDTokenIsCToken() public {
        dTokens.pop();
        dTokens.push(address(cBALRETH));

        vm.expectRevert(
            CentralRegistry.CentralRegistry__ParametersMisconfigured.selector
        );
        centralRegistry.withdrawReservesMulti(dTokens);
    }

    function test_withdrawReservesMulti_success() public {
        assertEq(usdc.balanceOf(address(dUSDC)), 100e6 + 42069);
        assertEq(dai.balanceOf(address(dDAI)), 100e18 + 42069);

        centralRegistry.withdrawReservesMulti(dTokens);

        assertEq(usdc.balanceOf(address(dUSDC)), 42069);
        assertEq(dai.balanceOf(address(dDAI)), 42069);
    }
}
