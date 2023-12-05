// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseVeCVE } from "../TestBaseVeCVE.sol";
import { SafeTransferLib } from "contracts/libraries/external/SafeTransferLib.sol";
import { VeCVE } from "contracts/token/VeCVE.sol";
import { WAD } from "contracts/libraries/Constants.sol";

contract LockTest is TestBaseVeCVE {
    event Locked(address indexed user, uint256 amount);
    event RewardPaid(address user, address rewardToken, uint256 amount);

    function test_lock_fail_whenVeCVEShutdown(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        veCVE.shutdown();

        vm.expectRevert(VeCVE.VeCVE__VeCVEShutdown.selector);
        veCVE.createLock(100e18, true, rewardsData, "", 0);
    }

    function test_lock_fail_whenAmountIsZero(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        vm.expectRevert(VeCVE.VeCVE__InvalidLock.selector);
        veCVE.createLock(0, true, rewardsData, "", 0);
    }

    function test_lock_fail_whenBalanceIsNotEnough(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        vm.expectRevert(SafeTransferLib.TransferFromFailed.selector);
        veCVE.createLock(100e18, true, rewardsData, "", 0);
    }

    function test_lock_fail_whenAllowanceIsNotEnough(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        deal(address(cve), address(this), 100e18);

        vm.expectRevert(SafeTransferLib.TransferFromFailed.selector);
        veCVE.createLock(100e18, true, rewardsData, "", 0);
    }

    function test_lock_success_withContinuousLock_fuzzed(
        uint256 amount,
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        deal(address(cve), address(this), 100e18);
        cve.approve(address(veCVE), 100e18);

        vm.assume(amount > 1e18 && amount <= 100e18);

        vm.expectEmit(true, true, true, true, address(veCVE));
        emit Locked(address(this), amount);

        veCVE.createLock(amount, true, rewardsData, "", 0);

        assertEq(cve.balanceOf(address(this)), 0);
        assertEq(veCVE.balanceOf(address(this)), amount);

        (, uint40 unlockTime) = veCVE.userLocks(address(this), 0);

        assertEq(
            veCVE.chainPoints(),
            amount * veCVE.CL_POINT_MULTIPLIER()
        );
        assertEq(
            veCVE.userPoints(address(this)),
            amount * veCVE.CL_POINT_MULTIPLIER()
        );
        assertEq(veCVE.chainUnlocksByEpoch(veCVE.currentEpoch(unlockTime)), 0);
        assertEq(
            veCVE.userUnlocksByEpoch(
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

        vm.assume(amount > 1e18 && amount <= 100e18);

        vm.expectEmit(true, true, true, true, address(veCVE));
        emit Locked(address(this), amount);

        veCVE.createLock(amount, false, rewardsData, "", 0);

        assertEq(cve.balanceOf(address(this)), 0);
        assertEq(veCVE.balanceOf(address(this)), amount);

        (, uint40 unlockTime) = veCVE.userLocks(address(this), 0);

        assertEq(veCVE.chainPoints(), amount);
        assertEq(veCVE.userPoints(address(this)), amount);
        assertEq(
            veCVE.chainUnlocksByEpoch(veCVE.currentEpoch(unlockTime)),
            amount
        );
        assertEq(
            veCVE.userUnlocksByEpoch(
                address(this),
                veCVE.currentEpoch(unlockTime)
            ),
            amount
        );
    }

    function test_lock_with_claimRewards(
        uint256 amount,
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        amount = bound(amount, 2, _MAX_FUZZ_AMOUNT);
        deal(address(cve), address(this), amount);
        cve.approve(address(veCVE), amount);

        vm.expectEmit(true, true, true, true, address(veCVE));
        emit Locked(address(this), amount / 2);
        veCVE.createLock(amount / 2, false, rewardsData, "", 0);

        // verify that rewards are delivered
        vm.expectEmit(true, true, true, true, address(cveLocker));
        emit RewardPaid(address(this), _USDC_ADDRESS, amount / 2);
        veCVE.createLock(amount / 2, false, rewardsData, "", 0);
        assertEq(usdc.balanceOf(address(this)), amount / 2);
    }
}
