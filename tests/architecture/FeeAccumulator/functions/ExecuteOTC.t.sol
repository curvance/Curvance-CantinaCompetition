// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseFeeAccumulator } from "../TestBaseFeeAccumulator.sol";
import { FeeAccumulator } from "contracts/architecture/FeeAccumulator.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { MockV3Aggregator } from "contracts/mocks/MockV3Aggregator.sol";

contract ExecuteOTCTest is TestBaseFeeAccumulator {
    function setUp() public override {
        super.setUp();

        chainlinkEthUsd = new MockV3Aggregator(8, 1500e8, 1e50, 1e6);
        _deployOracleRouter();
        _deployChainlinkAdaptors();
    }

    function test_executeOTC_fail_whenCallerIsNotAuthorized() public {
        vm.prank(user1);

        vm.expectRevert(FeeAccumulator.FeeAccumulator__Unauthorized.selector);
        feeAccumulator.executeOTC(_WETH_ADDRESS, _ONE);
    }

    function test_executeOTC_fail_whenTokenIsNotEarmarked() public {
        vm.expectRevert(
            FeeAccumulator.FeeAccumulator__TokenIsNotEarmarked.selector
        );
        feeAccumulator.executeOTC(_WETH_ADDRESS, _ONE);
    }

    function test_executeOTC_fail_whenFeeTokenIsNotApproved() public {
        feeAccumulator.setEarmarked(_WETH_ADDRESS, true);

        vm.expectRevert();
        feeAccumulator.executeOTC(_WETH_ADDRESS, _ONE);
    }

    function test_executeOTC_fail_whenGelatoOneBalanceIsInvalid() public {
        feeAccumulator.setEarmarked(_WETH_ADDRESS, true);

        skip(10 days);
        usdc.approve(address(feeAccumulator), _ONE);

        vm.expectRevert(
            FeeAccumulator.FeeAccumulator__ConfigurationError.selector
        );
        feeAccumulator.executeOTC(_WETH_ADDRESS, _ONE);
    }

    function test_executeOTC_success() public {
        feeAccumulator.setEarmarked(_WETH_ADDRESS, true);

        deal(_USDC_ADDRESS, address(this), _ONE);
        deal(_WETH_ADDRESS, address(feeAccumulator), _ONE);

        assertEq(IERC20(_WETH_ADDRESS).balanceOf(address(this)), 0);
        assertEq(usdc.balanceOf(address(oneBalanceFeeManager)), 0);

        usdc.approve(address(feeAccumulator), _ONE);

        feeAccumulator.executeOTC(_WETH_ADDRESS, _ONE);

        assertLt(usdc.balanceOf(address(this)), _ONE);
        assertLt(
            IERC20(_WETH_ADDRESS).balanceOf(address(feeAccumulator)),
            _ONE
        );
        assertEq(IERC20(_WETH_ADDRESS).balanceOf(address(this)), _ONE);
        assertGt(usdc.balanceOf(address(oneBalanceFeeManager)), 0);
    }
}
