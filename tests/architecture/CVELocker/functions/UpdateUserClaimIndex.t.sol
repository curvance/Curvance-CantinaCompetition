// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseCVELocker } from "../TestBaseCVELocker.sol";

contract UpdateUserClaimIndexTest is TestBaseCVELocker {
    function test_updateUserClaimIndex_fail_whenCallerIsVeCVE() public {
        vm.expectRevert(bytes4(keccak256(bytes("CVELocker__Unauthorized()"))));
        cveLocker.updateUserClaimIndex(user1, 1);
    }

    function test_updateUserClaimIndex_success() public {
        assertEq(cveLocker.userNextClaimIndex(user1), 0);

        vm.prank(address(cveLocker.veCVE()));
        cveLocker.updateUserClaimIndex(user1, 1);

        assertEq(cveLocker.userNextClaimIndex(user1), 1);
    }
}
