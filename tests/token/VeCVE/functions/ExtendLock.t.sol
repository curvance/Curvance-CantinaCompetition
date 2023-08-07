// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseVeCVE } from "../TestBaseVeCVE.sol";
import { VeCVE } from "contracts/token/VeCVE.sol";

contract ExtendLockTest is TestBaseVeCVE {
    function setUp() public override {
        super.setUp();

        deal(address(cve), address(this), 100e18);
        cve.approve(address(veCVE), 100e18);

        veCVE.lock(50e18, false, address(this), rewardsData, "", 0);
    }

    function test_extendLock_fail_whenVeCVEShutdown(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        veCVE.shutdown();

        vm.expectRevert(VeCVE.VeCVE_VeCVEShutdown.selector);
        veCVE.extendLock(0, true, address(this), rewardsData, "", 0);
    }

    function test_extendLock_fail_whenLockIndexIsInvalid(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        vm.expectRevert(VeCVE.VeCVE_InvalidLock.selector);
        veCVE.extendLock(1, true, address(this), rewardsData, "", 0);
    }

    function test_extendLock_fail_whenUnlockTimestampIsExpired(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        (, uint40 unlockTime) = veCVE.userLocks(address(this), 0);
        vm.warp(unlockTime + 1);

        vm.expectRevert(VeCVE.VeCVE_InvalidLock.selector);
        veCVE.extendLock(0, true, address(this), rewardsData, "", 0);
    }

    function test_extendLock_fail_whenContinuousLock(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        veCVE.lock(10e18, true, address(this), rewardsData, "", 0);

        vm.expectRevert(VeCVE.VeCVE_ContinuousLock.selector);
        veCVE.extendLock(1, true, address(this), rewardsData, "", 0);
    }

    function test_extendLock_success_withContinuousLock(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        veCVE.extendLock(0, true, address(this), rewardsData, "", 0);

        (, uint40 unlockTime) = veCVE.userLocks(address(this), 0);
        assertEq(unlockTime, veCVE.CONTINUOUS_LOCK_VALUE());
    }

    function test_extendLock_success_withDiscontinuousLock(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        veCVE.extendLock(0, false, address(this), rewardsData, "", 0);

        (, uint40 unlockTime) = veCVE.userLocks(address(this), 0);
        assertEq(unlockTime, veCVE.freshLockTimestamp());
    }
}
