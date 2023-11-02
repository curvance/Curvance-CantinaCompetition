// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseFeeAccumulator } from "../TestBaseFeeAccumulator.sol";
import { FeeAccumulator } from "contracts/architecture/FeeAccumulator.sol";

contract RemoveRewardTokenTest is TestBaseFeeAccumulator {
    address[] public tokens;

    function setUp() public override {
        super.setUp();

        tokens.push(_WETH_ADDRESS);
        tokens.push(_DAI_ADDRESS);

        feeAccumulator.addRewardTokens(tokens);
    }

    function test_removeRewardToken_fail_whenCallerIsNotAuthorized() public {
        vm.prank(user1);

        vm.expectRevert(FeeAccumulator.FeeAccumulator__Unauthorized.selector);
        feeAccumulator.removeRewardToken(_WETH_ADDRESS);
    }

    function test_removeRewardToken_fail_whenTokenIsNotRewardToken() public {
        vm.expectRevert(
            FeeAccumulator
                .FeeAccumulator__RemovalTokenIsNotRewardToken
                .selector
        );
        feeAccumulator.removeRewardToken(_USDT_ADDRESS);
    }

    function test_removeRewardToken_success() public {
        for (uint256 i = 0; i < tokens.length; i++) {
            (uint256 isRewardToken, uint256 forOTC) = feeAccumulator
                .rewardTokenInfo(tokens[i]);
            assertEq(isRewardToken, 2);
            assertEq(forOTC, 1);

            feeAccumulator.removeRewardToken(tokens[i]);

            (isRewardToken, forOTC) = feeAccumulator.rewardTokenInfo(
                tokens[i]
            );
            assertEq(isRewardToken, 1);
            assertEq(forOTC, 1);
        }

        vm.expectRevert();
        feeAccumulator.rewardTokens(0);
    }
}
