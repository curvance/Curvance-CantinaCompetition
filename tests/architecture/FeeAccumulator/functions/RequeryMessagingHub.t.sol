// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseFeeAccumulator } from "../TestBaseFeeAccumulator.sol";
import { FeeAccumulator } from "contracts/architecture/FeeAccumulator.sol";

contract RequeryMessagingHubTest is TestBaseFeeAccumulator {
    function test_requeryMessagingHub_fail_whenCallerIsNotAuthorized() public {
        vm.prank(user1);

        vm.expectRevert(FeeAccumulator.FeeAccumulator__Unauthorized.selector);
        feeAccumulator.requeryMessagingHub();
    }

    function test_requeryMessagingHub_success() public {
        address oldMessagingHub = centralRegistry.protocolMessagingHub();
        address newMessagingHub = makeAddr("newMessagingHub");

        assertNotEq(
            usdc.allowance(address(feeAccumulator), oldMessagingHub),
            0
        );
        assertEq(usdc.allowance(address(feeAccumulator), newMessagingHub), 0);

        centralRegistry.setProtocolMessagingHub(newMessagingHub);

        feeAccumulator.requeryMessagingHub();

        assertEq(centralRegistry.protocolMessagingHub(), newMessagingHub);
        assertEq(usdc.allowance(address(feeAccumulator), oldMessagingHub), 0);
        assertEq(
            usdc.allowance(address(feeAccumulator), newMessagingHub),
            type(uint256).max
        );
    }
}
