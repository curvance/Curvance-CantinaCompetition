// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseCVELocker } from "../TestBaseCVELocker.sol";
import { CVELocker } from "contracts/architecture/CVELocker.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract StartLockerTest is TestBaseCVELocker {
    function setUp() public override {
        super.setUp();

        cveLocker = new CVELocker(
            ICentralRegistry(address(centralRegistry)),
            _CVX_ADDRESS,
            _CVX_LOCKER_ADDRESS,
            _USDC_ADDRESS
        );
    }

    function test_startLocker_fail_whenCallerIsNotAuthorized() public {
        vm.prank(address(1));

        vm.expectRevert("CVELocker: UNAUTHORIZED");
        cveLocker.startLocker();
    }

    function test_startLocker_fail_whenLockerIsAlreadyStarted() public {
        cveLocker.startLocker();

        vm.expectRevert("CVELocker: locker already started");
        cveLocker.startLocker();
    }

    function test_startLocker_success() public {
        assertEq(cveLocker.lockerStarted(), 1);
        assertEq(address(cveLocker.veCVE()), address(0));

        cveLocker.startLocker();

        assertEq(cveLocker.lockerStarted(), 2);
        assertEq(address(cveLocker.veCVE()), centralRegistry.veCVE());
    }
}
