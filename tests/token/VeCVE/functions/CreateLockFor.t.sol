// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseVeCVE } from "../TestBaseVeCVE.sol";
import { SafeTransferLib } from "contracts/libraries/external/SafeTransferLib.sol";
import { VeCVE } from "contracts/token/VeCVE.sol";

contract CreateLockForTest is TestBaseVeCVE {
    event Locked(address indexed user, uint256 amount);

    function test_createLockFor_fail_whenVeCVEShutdown(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        veCVE.shutdown();

        vm.expectRevert(VeCVE.VeCVE__VeCVEShutdown.selector);
        veCVE.createLockFor(user1, 100e18, true, rewardsData, "", 0);
    }

    function test_createLockFor_fail_whenAmountIsZero(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        vm.expectRevert(VeCVE.VeCVE__InvalidLock.selector);
        veCVE.createLockFor(user1, 0, true, rewardsData, "", 0);
    }

    function test_createLockFor_fail_whenLockerIsNotApproved(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        vm.expectRevert(VeCVE.VeCVE__InvalidLock.selector);
        veCVE.createLockFor(user1, 100e18, true, rewardsData, "", 0);
    }

    function test_createLockFor_fail_whenBalanceIsNotEnough(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        centralRegistry.addVeCVELocker(address(this));

        vm.expectRevert(SafeTransferLib.TransferFromFailed.selector);
        veCVE.createLockFor(user1, 100e18, true, rewardsData, "", 0);
    }

    function test_createLockFor_fail_whenAllowanceIsNotEnough(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        centralRegistry.addVeCVELocker(address(this));

        deal(address(cve), address(this), 100e18);

        vm.expectRevert(SafeTransferLib.TransferFromFailed.selector);
        veCVE.createLockFor(user1, 100e18, true, rewardsData, "", 0);
    }

    function test_createLockFor_success_withContinuousLock_fuzzed(
        uint256 amount,
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        centralRegistry.addVeCVELocker(address(this));

        deal(address(cve), address(this), 100e18);
        cve.approve(address(veCVE), 100e18);

        (uint256[] memory lockAmounts, uint256[] memory lockTimestamps) = veCVE
            .queryUserLocks(user1);

        assertEq(lockAmounts.length, 0);
        assertEq(lockTimestamps.length, 0);

        vm.assume(amount > 1e18 && amount <= 100e18);

        vm.expectEmit(true, true, true, true, address(veCVE));
        emit Locked(user1, amount);

        veCVE.createLockFor(user1, amount, true, rewardsData, "", 0);

        assertEq(cve.balanceOf(address(this)), 100e18 - amount);
        assertEq(veCVE.balanceOf(user1), amount);

        (lockAmounts, lockTimestamps) = veCVE.queryUserLocks(user1);
        (, uint40 unlockTime) = veCVE.userLocks(user1, 0);

        assertEq(lockAmounts.length, 1);
        assertEq(lockTimestamps.length, 1);
        assertEq(lockAmounts[0], amount);
        assertEq(lockTimestamps[0], unlockTime);
        assertEq(unlockTime, veCVE.CONTINUOUS_LOCK_VALUE());

        assertEq(veCVE.chainPoints(), amount * veCVE.CL_POINT_MULTIPLIER());
        assertEq(
            veCVE.userPoints(user1),
            amount * veCVE.CL_POINT_MULTIPLIER()
        );
        assertEq(veCVE.chainUnlocksByEpoch(veCVE.currentEpoch(unlockTime)), 0);
        assertEq(
            veCVE.userUnlocksByEpoch(user1, veCVE.currentEpoch(unlockTime)),
            0
        );
    }

    function test_createLockFor_success_withDiscontinuousLock_fuzzed(
        uint256 amount,
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        centralRegistry.addVeCVELocker(address(this));

        deal(address(cve), address(this), 100e18);
        cve.approve(address(veCVE), 100e18);

        (uint256[] memory lockAmounts, uint256[] memory lockTimestamps) = veCVE
            .queryUserLocks(user1);

        assertEq(lockAmounts.length, 0);
        assertEq(lockTimestamps.length, 0);

        vm.assume(amount > 1e18 && amount <= 100e18);

        uint256 timestamp = block.timestamp;

        vm.expectEmit(true, true, true, true, address(veCVE));
        emit Locked(user1, amount);

        veCVE.createLockFor(user1, amount, false, rewardsData, "", 0);

        assertEq(cve.balanceOf(address(this)), 100e18 - amount);
        assertEq(veCVE.balanceOf(user1), amount);

        (lockAmounts, lockTimestamps) = veCVE.queryUserLocks(user1);
        (, uint40 unlockTime) = veCVE.userLocks(user1, 0);

        assertEq(lockAmounts.length, 1);
        assertEq(lockTimestamps.length, 1);
        assertEq(lockAmounts[0], amount);
        assertEq(lockTimestamps[0], unlockTime);
        assertEq(
            unlockTime,
            veCVE.genesisEpoch() +
                (veCVE.currentEpoch(timestamp) * veCVE.EPOCH_DURATION()) +
                veCVE.LOCK_DURATION()
        );

        assertEq(veCVE.chainPoints(), amount);
        assertEq(veCVE.userPoints(user1), amount);
        assertEq(
            veCVE.chainUnlocksByEpoch(veCVE.currentEpoch(unlockTime)),
            amount
        );
        assertEq(
            veCVE.userUnlocksByEpoch(user1, veCVE.currentEpoch(unlockTime)),
            amount
        );
    }
}
