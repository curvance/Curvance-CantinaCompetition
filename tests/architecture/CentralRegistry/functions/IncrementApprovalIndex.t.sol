// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { CentralRegistry } from "contracts/architecture/CentralRegistry.sol";

contract IncrementApprovalIndexTest is TestBaseMarket {
    event ApprovalIndexIncremented(address indexed user, uint256 newIndex);

    function test_incrementApprovalIndex_success() public {
        assertEq(centralRegistry.userApprovalIndex(user1), 0);

        vm.prank(user1);

        vm.expectEmit(true, true, true, true);
        emit ApprovalIndexIncremented(user1, 1);

        centralRegistry.incrementApprovalIndex();

        assertEq(centralRegistry.userApprovalIndex(user1), 1);
    }
}
