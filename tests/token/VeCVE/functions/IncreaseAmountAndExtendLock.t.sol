// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseVeCVE } from "../TestBaseVeCVE.sol";
import { VeCVE } from "contracts/token/VeCVE.sol";

contract IncreaseAmountAndExtendLockTest is TestBaseVeCVE {
    function setUp() public override {
        super.setUp();

        deal(address(cve), address(this), 100e18);
        cve.approve(address(veCVE), 100e18);

        veCVE.lock(50e18, false, address(this), rewardsData, "", 0);
    }

    function test_increaseAmountAndExtendLock_fail_whenVeCVEShutdown(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        veCVE.shutdown();

        vm.expectRevert(VeCVE.VeCVE_VeCVEShutdown.selector);
        veCVE.increaseAmountAndExtendLock(
            100,
            0,
            true,
            address(this),
            rewardsData,
            "",
            0
        );
    }

    function test_increaseAmountAndExtendLock_fail_whenAmountIsZero(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        vm.expectRevert(VeCVE.VeCVE_InvalidLock.selector);
        veCVE.increaseAmountAndExtendLock(
            0,
            0,
            true,
            address(this),
            rewardsData,
            "",
            0
        );
    }

    function test_increaseAmountAndExtendLock_fail_whenLockIndexIsInvalid(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        vm.expectRevert(VeCVE.VeCVE_InvalidLock.selector);
        veCVE.increaseAmountAndExtendLock(
            100,
            1,
            true,
            address(this),
            rewardsData,
            "",
            0
        );
    }

    function test_increaseAmountAndExtendLock_fail_whenUnlockTimestampIsExpired(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        (, uint40 unlockTime) = veCVE.userLocks(address(this), 0);
        vm.warp(unlockTime + 1);

        vm.expectRevert(VeCVE.VeCVE_InvalidLock.selector);
        veCVE.increaseAmountAndExtendLock(
            100,
            0,
            true,
            address(this),
            rewardsData,
            "",
            0
        );
    }

    function test_increaseAmountAndExtendLock_success_withContinuousLock(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        veCVE.increaseAmountAndExtendLock(
            100,
            0,
            true,
            address(this),
            rewardsData,
            "",
            0
        );

        (, uint40 unlockTime) = veCVE.userLocks(address(this), 0);
        assertEq(unlockTime, veCVE.CONTINUOUS_LOCK_VALUE());
    }

    function test_increaseAmountAndExtendLock_success_withDiscontinuousLock(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        veCVE.increaseAmountAndExtendLock(
            100,
            0,
            false,
            address(this),
            rewardsData,
            "",
            0
        );

        (, uint40 unlockTime) = veCVE.userLocks(address(this), 0);
        assertEq(unlockTime, veCVE.freshLockTimestamp());
    }
}
