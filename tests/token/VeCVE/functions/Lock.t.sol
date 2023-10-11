// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseVeCVE } from "../TestBaseVeCVE.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";
import { VeCVE } from "contracts/token/VeCVE.sol";

contract LockTest is TestBaseVeCVE {
    event Locked(address indexed user, uint256 amount);

    function test_lock_fail_whenVeCVEShutdown(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        veCVE.shutdown();

        vm.expectRevert(VeCVE.VeCVE__VeCVEShutdown.selector);
        veCVE.lock(100, true, address(this), rewardsData, "", 0);
    }

    function test_lock_fail_whenAmountIsZero(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        vm.expectRevert(VeCVE.VeCVE__InvalidLock.selector);
        veCVE.lock(0, true, address(this), rewardsData, "", 0);
    }

    function test_lock_fail_whenBalanceIsNotEnough(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        vm.expectRevert(SafeTransferLib.TransferFromFailed.selector);
        veCVE.lock(100, true, address(this), rewardsData, "", 0);
    }

    function test_lock_fail_whenAllowanceIsNotEnough(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        deal(address(cve), address(this), 100e18);

        vm.expectRevert(SafeTransferLib.TransferFromFailed.selector);
        veCVE.lock(100, true, address(this), rewardsData, "", 0);
    }

    function test_lock_success_withContinuousLock_fuzzed(
        uint256 amount,
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        deal(address(cve), address(this), 100e18);
        cve.approve(address(veCVE), 100e18);

        vm.assume(amount > 0 && amount <= 100e18);

        vm.expectEmit(true, true, true, true, address(veCVE));
        emit Locked(address(this), amount);

        veCVE.lock(amount, true, address(this), rewardsData, "", 0);

        assertEq(cve.balanceOf(address(this)), 100e18 - amount);
        assertEq(veCVE.balanceOf(address(this)), amount);

        (, uint40 unlockTime) = veCVE.userLocks(address(this), 0);

        assertEq(
            veCVE.chainTokenPoints(),
            (amount * veCVE.clPointMultiplier()) / veCVE.DENOMINATOR()
        );
        assertEq(
            veCVE.userTokenPoints(address(this)),
            (amount * veCVE.clPointMultiplier()) / veCVE.DENOMINATOR()
        );
        assertEq(veCVE.chainUnlocksByEpoch(veCVE.currentEpoch(unlockTime)), 0);
        assertEq(
            veCVE.userTokenUnlocksByEpoch(
                address(this),
                veCVE.currentEpoch(unlockTime)
            ),
            0
        );
    }

    function test_lock_success_withDiscontinuousLock_fuzzed(
        uint256 amount,
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        deal(address(cve), address(this), 100e18);
        cve.approve(address(veCVE), 100e18);

        vm.assume(amount > 0 && amount <= 100e18);

        vm.expectEmit(true, true, true, true, address(veCVE));
        emit Locked(address(this), amount);

        veCVE.lock(amount, false, address(this), rewardsData, "", 0);

        assertEq(cve.balanceOf(address(this)), 100e18 - amount);
        assertEq(veCVE.balanceOf(address(this)), amount);

        (, uint40 unlockTime) = veCVE.userLocks(address(this), 0);

        assertEq(veCVE.chainTokenPoints(), amount);
        assertEq(veCVE.userTokenPoints(address(this)), amount);
        assertEq(
            veCVE.chainUnlocksByEpoch(veCVE.currentEpoch(unlockTime)),
            amount
        );
        assertEq(
            veCVE.userTokenUnlocksByEpoch(
                address(this),
                veCVE.currentEpoch(unlockTime)
            ),
            amount
        );
    }
}
