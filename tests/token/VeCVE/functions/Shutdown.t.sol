// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseVeCVE } from "../TestBaseVeCVE.sol";

contract ShutdownTest is TestBaseVeCVE {
    function test_shutdown_fail_whenCallerIsNotAuthorized() public {
        vm.prank(address(1));

        vm.expectRevert(VeCVE.VeCVE__Unauthorized.selector);
        veCVE.shutdown();
    }

    function test_shutdown_success() public {
        assertEq(veCVE.isShutdown(), 1);

        veCVE.shutdown();

        assertEq(veCVE.isShutdown(), 2);
    }
}
