// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseFeeAccumulator } from "../TestBaseFeeAccumulator.sol";
import { FeeAccumulator } from "contracts/architecture/FeeAccumulator.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract MigrateFeeAccumulatorTest is TestBaseFeeAccumulator {
    function test_migrateFeeAccumulator_fail_whenNewFeeAccumulatorIsNotRegistered()
        public
    {
        vm.expectRevert(
            FeeAccumulator
                .FeeAccumulator__NewFeeAccumulatorIsNotChanged
                .selector
        );
        feeAccumulator.migrateFeeAccumulator();
    }

    function test_migrateFeeAccumulator_success() public {
        address[] memory rewardTokens = new address[](2);
        rewardTokens[0] = _DAI_ADDRESS;
        rewardTokens[1] = _BALANCER_WETH_RETH;

        feeAccumulator.addRewardTokens(rewardTokens);

        deal(_DAI_ADDRESS, address(feeAccumulator), _ONE);
        deal(_BALANCER_WETH_RETH, address(feeAccumulator), _ONE);

        uint256[] memory rewardTokenBalances = feeAccumulator
            .getRewardTokenBalances();

        for (uint256 i = 0; i < rewardTokenBalances.length; i++) {
            assertEq(rewardTokenBalances[i], _ONE);
        }

        uint256 feeTokenBalance = usdc.balanceOf(address(feeAccumulator));

        FeeAccumulator newFeeAccumulator = new FeeAccumulator(
            ICentralRegistry(address(centralRegistry)),
            _USDC_ADDRESS,
            1e9,
            1e9
        );
        centralRegistry.setFeeAccumulator(address(newFeeAccumulator));

        feeAccumulator.migrateFeeAccumulator();

        assertEq(dai.balanceOf(address(feeAccumulator)), 0);
        assertEq(dai.balanceOf(address(newFeeAccumulator)), _ONE);
        assertEq(balRETH.balanceOf(address(feeAccumulator)), 0);
        assertEq(balRETH.balanceOf(address(newFeeAccumulator)), _ONE);
        assertEq(usdc.balanceOf(address(feeAccumulator)), 0);
        assertEq(usdc.balanceOf(address(newFeeAccumulator)), feeTokenBalance);
    }
}
