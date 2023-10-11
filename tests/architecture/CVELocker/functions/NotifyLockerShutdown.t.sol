// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseCVELocker } from "../TestBaseCVELocker.sol";
import { CVELocker } from "contracts/architecture/CVELocker.sol";

contract NotifyLockerShutdownTest is TestBaseCVELocker {
    function test_notifyLockerShutdown_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.prank(address(1));

        vm.expectRevert(CVELocker.CVELocker__Unauthorized.selector);
        cveLocker.notifyLockerShutdown();
    }

    function test_notifyLockerShutdown_success_fromVeCVE() public {
        assertEq(cveLocker.isShutdown(), 1);

        vm.prank(address(cveLocker.veCVE()));
        cveLocker.notifyLockerShutdown();

        assertEq(cveLocker.isShutdown(), 2);
    }

    function test_notifyLockerShutdown_success() public {
        assertEq(cveLocker.isShutdown(), 1);

        cveLocker.notifyLockerShutdown();

        assertEq(cveLocker.isShutdown(), 2);
    }
}
