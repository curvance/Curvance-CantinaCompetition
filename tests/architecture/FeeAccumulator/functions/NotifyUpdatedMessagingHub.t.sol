// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseFeeAccumulator } from "../TestBaseFeeAccumulator.sol";
import { FeeAccumulator } from "contracts/architecture/FeeAccumulator.sol";

contract notifyUpdatedMessagingHubTest is TestBaseFeeAccumulator {
    function test_notifyUpdatedMessagingHub_fail_whenCallerIsNotAuthorized() public {
        vm.prank(user1);

        vm.expectRevert(FeeAccumulator.FeeAccumulator__Unauthorized.selector);
        feeAccumulator.notifyUpdatedMessagingHub();
    }

    function test_notifyUpdatedMessagingHub_fail_whenMessagingHubHasNotChanged() public {
        address oldMessagingHub = centralRegistry.protocolMessagingHub();

        vm.expectRevert(FeeAccumulator.FeeAccumulator__MessagingHubHasNotChanged.selector);
        centralRegistry.setProtocolMessagingHub(oldMessagingHub);
    }

    function test_notifyUpdatedMessagingHub_success() public {
        address oldMessagingHub = centralRegistry.protocolMessagingHub();
        address newMessagingHub = makeAddr("newMessagingHub");

        assertNotEq(
            usdc.allowance(address(feeAccumulator), oldMessagingHub),
            0
        );
        assertEq(usdc.allowance(address(feeAccumulator), newMessagingHub), 0);

        centralRegistry.setProtocolMessagingHub(newMessagingHub);

        assertEq(centralRegistry.protocolMessagingHub(), newMessagingHub);
        assertEq(usdc.allowance(address(feeAccumulator), oldMessagingHub), 0);
        assertEq(
            usdc.allowance(address(feeAccumulator), newMessagingHub),
            type(uint256).max
        );
    }
}
