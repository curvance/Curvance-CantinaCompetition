// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseVeCVE } from "../TestBaseVeCVE.sol";
import { VeCVE } from "contracts/token/VeCVE.sol";

contract CombineAllLocksTest is TestBaseVeCVE {
    function setUp() public override {
        super.setUp();

        deal(address(cve), address(this), 100e18);
        cve.approve(address(veCVE), 100e18);

        veCVE.createLock(30e18, false, rewardsData, "", 0);
    }

    function test_combineAllLocks_fail_whenCombineOneLock(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        vm.expectRevert(VeCVE.VeCVE__InvalidLock.selector);
        veCVE.combineAllLocks(false, rewardsData, "", 0);
    }

    function test_combineAllLocks_success_withContinuousLock(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        veCVE.createLock(30e18, true, rewardsData, "", 0);

        (uint256 lockAmount, uint40 unlockTime) = veCVE.userLocks(
            address(this),
            1
        );

        assertEq(veCVE.chainPoints(), 90e18);
        assertEq(veCVE.userPoints(address(this)), 90e18);
        assertEq(veCVE.chainUnlocksByEpoch(veCVE.currentEpoch(unlockTime)), 0);
        assertEq(
            veCVE.userUnlocksByEpoch(
                address(this),
                veCVE.currentEpoch(unlockTime)
            ),
            0
        );

        veCVE.combineAllLocks(true, rewardsData, "", 0);

        vm.expectRevert();
        veCVE.userLocks(address(this), 1);

        (lockAmount, unlockTime) = veCVE.userLocks(address(this), 0);

        assertEq(lockAmount, 60e18);
        assertEq(unlockTime, veCVE.CONTINUOUS_LOCK_VALUE());
        assertEq(veCVE.chainPoints(), 120e18);
        assertEq(veCVE.userPoints(address(this)), 120e18);
        assertEq(veCVE.chainUnlocksByEpoch(veCVE.currentEpoch(unlockTime)), 0);
        assertEq(
            veCVE.userUnlocksByEpoch(
                address(this),
                veCVE.currentEpoch(unlockTime)
            ),
            0
        );
    }

    function test_combineAllLocks_success_withDiscontinuousLock(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        veCVE.createLock(30e18, true, rewardsData, "", 0);

        (uint256 lockAmount, uint40 unlockTime) = veCVE.userLocks(
            address(this),
            1
        );

        assertEq(veCVE.chainPoints(), 90e18);
        assertEq(veCVE.userPoints(address(this)), 90e18);
        assertEq(veCVE.chainUnlocksByEpoch(veCVE.currentEpoch(unlockTime)), 0);
        assertEq(
            veCVE.userUnlocksByEpoch(
                address(this),
                veCVE.currentEpoch(unlockTime)
            ),
            0
        );

        veCVE.combineAllLocks(false, rewardsData, "", 0);

        vm.expectRevert();
        veCVE.userLocks(address(this), 1);

        (lockAmount, unlockTime) = veCVE.userLocks(address(this), 0);

        assertEq(lockAmount, 60e18);
        assertEq(unlockTime, veCVE.freshLockTimestamp());
        assertEq(veCVE.chainPoints(), 60e18);
        assertEq(veCVE.userPoints(address(this)), 60e18);
        assertEq(
            veCVE.chainUnlocksByEpoch(veCVE.currentEpoch(unlockTime)),
            60e18
        );
        assertEq(
            veCVE.userUnlocksByEpoch(
                address(this),
                veCVE.currentEpoch(unlockTime)
            ),
            60e18
        );
    }
}
