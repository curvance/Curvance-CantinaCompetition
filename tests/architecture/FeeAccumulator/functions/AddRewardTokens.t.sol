// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseFeeAccumulator } from "../TestBaseFeeAccumulator.sol";
import { FeeAccumulator } from "contracts/architecture/FeeAccumulator.sol";

contract AddRewardTokensTest is TestBaseFeeAccumulator {
    address[] public tokens;

    function setUp() public override {
        super.setUp();

        tokens.push(_WETH_ADDRESS);
        tokens.push(_DAI_ADDRESS);
    }

    function test_addRewardTokens_fail_whenCallerIsNotAuthorized() public {
        vm.prank(user1);

        vm.expectRevert(FeeAccumulator.FeeAccumulator__Unauthorized.selector);
        feeAccumulator.addRewardTokens(tokens);
    }

    function test_addRewardTokens_fail_whenTokenLengthIsZero() public {
        tokens.pop();
        tokens.pop();

        vm.expectRevert(
            FeeAccumulator.FeeAccumulator__TokenLengthIsZero.selector
        );
        feeAccumulator.addRewardTokens(tokens);
    }

    function test_addRewardTokens_success() public {
        for (uint256 i = 0; i < tokens.length; i++) {
            (uint256 isRewardToken, uint256 forOTC) = feeAccumulator
                .rewardTokenInfo(tokens[i]);
            assertEq(isRewardToken, 0);
            assertEq(forOTC, 0);
        }

        feeAccumulator.addRewardTokens(tokens);

        for (uint256 i = 0; i < tokens.length; i++) {
            (uint256 isRewardToken, uint256 forOTC) = feeAccumulator
                .rewardTokenInfo(tokens[i]);
            assertEq(isRewardToken, 2);
            assertEq(forOTC, 1);
            assertEq(feeAccumulator.rewardTokens(i), tokens[i]);
        }
    }
}
