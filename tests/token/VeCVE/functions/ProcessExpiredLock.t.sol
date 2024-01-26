// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseVeCVE } from "../TestBaseVeCVE.sol";
import { VeCVE } from "contracts/token/VeCVE.sol";

contract ProcessExpiredLockTest is TestBaseVeCVE {
    event Unlocked(address indexed user, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 amount);

    function setUp() public override {
        super.setUp();

        deal(address(cve), address(this), 100e18);
        cve.approve(address(veCVE), 100e18);

        veCVE.createLock(30e18, false, rewardsData, "", 0);
    }

    function test_processExpiredLock_fail_whenLockIndexExceeds() public {
        // no need to set rewardsData because it will revert before
        vm.expectRevert(VeCVE.VeCVE__InvalidLock.selector);
        veCVE.processExpiredLock(
            1,
            false,
            false,
            rewardsData,
            "",
            0
        );
    }

    function test_processExpiredLock_fail_whenLockIsNotExpired() public {
        // no need to set rewardsData because it will revert before
        vm.expectRevert(VeCVE.VeCVE__InvalidLock.selector);
        veCVE.processExpiredLock(
            0,
            false,
            false,
            rewardsData,
            "",
            0
        );
    }

    function test_processExpiredLock_success_withContinuousLock(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        (, uint40 unlockTime) = veCVE.userLocks(address(this), 0);
        vm.warp(unlockTime);

        vm.expectEmit(true, true, true, true, address(veCVE));
        emit Unlocked(address(this), 30e18);

        veCVE.processExpiredLock(
            0,
            false,
            true,
            rewardsData,
            "",
            0
        );
    }

    function test_processExpiredLock_success_withDiscontinuousLock(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        (, uint40 unlockTime) = veCVE.userLocks(address(this), 0);
        vm.warp(unlockTime);

        vm.expectEmit(true, true, true, true, address(veCVE));
        emit Unlocked(address(this), 30e18);

        veCVE.processExpiredLock(
            0,
            false,
            false,
            rewardsData,
            "",
            0
        );
    }

    // cover L680
    function test_processExpiredLock_success_withDiscontinuousLock_withRelock(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        (uint216 amount, uint40 unlockTime) =
            veCVE.userLocks(address(this), 0);
        vm.warp(unlockTime);

        veCVE.processExpiredLock(
            0,
            true,
            false,
            rewardsData,
            "",
            0
        );
        uint40 newLockTimestamp = veCVE.freshLockTimestamp();
        // lockIndex 0 is updated to new timestamp
        (uint216 amount2, uint40 unlockTime2) = veCVE.userLocks(address(this), 0);

        assertGt(unlockTime2, unlockTime);
        assertEq(unlockTime2, newLockTimestamp);
        assertEq(amount2, amount);
    }

    // cover L672
    function test_processExpiredLock_success_withDiscontinuousLock_withRelock_duringShutdown(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        (, uint40 unlockTime) = veCVE.userLocks(address(this), 0);
        vm.warp(unlockTime);

        veCVE.shutdown();

        vm.expectEmit(true, true, true, true, address(veCVE));
        emit Unlocked(address(this), 30e18);

        veCVE.processExpiredLock(
            0,
            true, // relock but it will be ignored because of shutdown
            false,
            rewardsData,
            "",
            0
        );
    }

    // cover L1117
    function test_processExpiredLock_sucess_withoutRelock_notLastIndex() public {
        (, uint40 unlockTime) = veCVE.userLocks(address(this), 0);
        vm.warp(unlockTime);

        veCVE.createLock(30e18, false, rewardsData, "", 0);
        (, uint40 unlockTime2) = veCVE.userLocks(address(this), 1);
        assertGt(unlockTime2, unlockTime);

        vm.expectEmit(true, true, true, true, address(veCVE));
        emit Unlocked(address(this), 30e18);

        veCVE.processExpiredLock(
            0,
            false,
            false,
            rewardsData,
            "",
            0
        );

        (, unlockTime) = veCVE.userLocks(address(this), 0);
        assertEq(unlockTime, unlockTime2);

        // except revert for invalid index because expired lock is removed
        vm.expectRevert();
        (, unlockTime) = veCVE.userLocks(address(this), 1);
    }
}
