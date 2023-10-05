// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseCVELocker } from "../TestBaseCVELocker.sol";
import { CVELocker } from "contracts/architecture/CVELocker.sol";

contract ResetUserClaimIndexTest is TestBaseCVELocker {
    function test_resetUserClaimIndex_fail_whenCallerIsVeCVE() public {
        vm.expectRevert(CVELocker.CVELocker__Unauthorized.selector);
        cveLocker.resetUserClaimIndex(user1);
    }

    function test_resetUserClaimIndex_success() public {
        vm.prank(address(cveLocker.veCVE()));
        cveLocker.updateUserClaimIndex(user1, 1);

        assertEq(cveLocker.userNextClaimIndex(user1), 1);

        vm.prank(address(cveLocker.veCVE()));
        cveLocker.resetUserClaimIndex(user1);

        assertEq(cveLocker.userNextClaimIndex(user1), 0);
    }
}
