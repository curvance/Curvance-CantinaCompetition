// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseVeCVE } from "../TestBaseVeCVE.sol";
import { VeCVE } from "contracts/token/VeCVE.sol";

contract IncreaseAmountAndExtendLockForTest is TestBaseVeCVE {
    function setUp() public override {
        super.setUp();

        deal(address(cve), address(this), 100e18);
        cve.approve(address(veCVE), 100e18);

        centralRegistry.addVeCVELocker(address(this));

        veCVE.lockFor(
            address(1),
            50e18,
            false,
            address(this),
            rewardsData,
            "",
            0
        );

        centralRegistry.removeVeCVELocker(address(this));
    }

    function test_increaseAmountAndExtendLockFor_fail_whenVeCVEShutdown(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        veCVE.shutdown();

        vm.expectRevert(VeCVE.VeCVE__VeCVEShutdown.selector);
        veCVE.increaseAmountAndExtendLockFor(
            address(1),
            100,
            0,
            true,
            address(this),
            rewardsData,
            "",
            0
        );
    }

    function test_increaseAmountAndExtendLockFor_fail_whenAmountIsZero(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        vm.expectRevert(VeCVE.VeCVE__InvalidLock.selector);
        veCVE.increaseAmountAndExtendLockFor(
            address(1),
            0,
            0,
            true,
            address(this),
            rewardsData,
            "",
            0
        );
    }

    function test_lockFor_fail_whenLockerIsNotApproved(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        vm.expectRevert(VeCVE.VeCVE__InvalidLock.selector);
        veCVE.increaseAmountAndExtendLockFor(
            address(1),
            100,
            0,
            true,
            address(this),
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
            100,
            1,
            true,
            address(this),
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
            100,
            0,
            true,
            address(this),
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
            100,
            0,
            true,
            address(this),
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
            100,
            0,
            false,
            address(this),
            rewardsData,
            "",
            0
        );

        (, uint40 unlockTime) = veCVE.userLocks(address(1), 0);
        assertEq(unlockTime, veCVE.freshLockTimestamp());
    }
}
