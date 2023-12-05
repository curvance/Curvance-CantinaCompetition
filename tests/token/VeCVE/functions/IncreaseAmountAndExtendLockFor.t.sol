// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseVeCVE } from "../TestBaseVeCVE.sol";
import { VeCVE } from "contracts/token/VeCVE.sol";

contract IncreaseAmountAndExtendLockForTest is TestBaseVeCVE {
    function setUp() public override {
        super.setUp();

        deal(address(cve), address(this), 100e18);
        cve.approve(address(veCVE), 100e18);

        centralRegistry.addVeCVELocker(address(this));

        veCVE.createLockFor(
            address(1),
            50e18,
            false,
            rewardsData,
            "",
            0
        );

        centralRegistry.removeVeCVELocker(address(this));
    }

    function test_increaseAmountAndExtendLockFor_fail_whenVeCVEShutdown() public {
        veCVE.shutdown();

        vm.expectRevert(VeCVE.VeCVE__VeCVEShutdown.selector);
        veCVE.increaseAmountAndExtendLockFor(
            address(1),
            30e18,
            0,
            true,
            rewardsData,
            "",
            0
        );
    }

    function test_increaseAmountAndExtendLockFor_fail_whenAmountIsZero() public {
        vm.expectRevert(VeCVE.VeCVE__InvalidLock.selector);
        veCVE.increaseAmountAndExtendLockFor(
            address(1),
            0,
            0,
            true,
            rewardsData,
            "",
            0
        );
    }

    function test_lockFor_fail_whenLockerIsNotApproved() public {
        vm.expectRevert(VeCVE.VeCVE__InvalidLock.selector);
        veCVE.increaseAmountAndExtendLockFor(
            address(1),
            30e18,
            0,
            true,
            rewardsData,
            "",
            0
        );
    }

    function test_increaseAmountAndExtendLockFor_fail_whenLockIndexIsInvalid(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        centralRegistry.addVeCVELocker(address(this));

        vm.expectRevert(VeCVE.VeCVE__InvalidLock.selector);
        veCVE.increaseAmountAndExtendLockFor(
            address(1),
            30e18,
            1,
            true,
            rewardsData,
            "",
            0
        );
    }

    function test_increaseAmountAndExtendLockFor_fail_whenUnlockTimestampIsExpired(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        centralRegistry.addVeCVELocker(address(this));

        (, uint40 unlockTime) = veCVE.userLocks(address(1), 0);
        vm.warp(unlockTime + 1);

        vm.expectRevert(VeCVE.VeCVE__InvalidLock.selector);
        veCVE.increaseAmountAndExtendLockFor(
            address(1),
            30e18,
            0,
            true,
            rewardsData,
            "",
            0
        );
    }

    function test_increaseAmountAndExtendLockFor_success_withContinuousLock(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        centralRegistry.addVeCVELocker(address(this));

        veCVE.increaseAmountAndExtendLockFor(
            address(1),
            30e18,
            0,
            true,
            rewardsData,
            "",
            0
        );

        (, uint40 unlockTime) = veCVE.userLocks(address(1), 0);
        assertEq(unlockTime, veCVE.CONTINUOUS_LOCK_VALUE());
    }

    function test_increaseAmountAndExtendLockFor_success_withDiscontinuousLock(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        centralRegistry.addVeCVELocker(address(this));

        veCVE.increaseAmountAndExtendLockFor(
            address(1),
            30e18,
            0,
            false,
            rewardsData,
            "",
            0
        );

        (, uint40 unlockTime) = veCVE.userLocks(address(1), 0);
        assertEq(unlockTime, veCVE.freshLockTimestamp());
    }

    function test_increaseAmountAndExtendLockFor_fail_startContinuousLock() public {
        centralRegistry.addVeCVELocker(address(this));

        veCVE.createLockFor(
            address(2),
            10e18,
            true,
            rewardsData,
            "",
            0
        );

        // cannot extned a continuous lock with a non-continuous lock
        vm.expectRevert(VeCVE.VeCVE__InvalidLock.selector);
        veCVE.increaseAmountAndExtendLockFor(
            address(2),
            1e18,
            0,
            false,
            rewardsData,
            "",
            0
        );
    }

    // cover L1059
    function test_increaseAmountAndExtendLockFor_success_startContinuousLock() public {
        centralRegistry.addVeCVELocker(address(this));

        veCVE.createLockFor(
            address(2),
            10e18,
            true,
            rewardsData,
            "",
            0
        );

        veCVE.increaseAmountAndExtendLockFor(
            address(2),
            1e18,
            0,
            true,
            rewardsData,
            "",
            0
        );

        (uint256 lockAmount, uint40 unlockTime) = veCVE.userLocks(address(2), 0);
        assertEq(lockAmount, 11e18);
        assertEq(unlockTime, veCVE.CONTINUOUS_LOCK_VALUE());

        // user points are multiplied by 2
        assertEq(veCVE.userPoints(address(2)), 22e18);
    }
}
