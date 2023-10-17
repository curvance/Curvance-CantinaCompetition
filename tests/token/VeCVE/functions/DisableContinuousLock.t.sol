// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseVeCVE } from "../TestBaseVeCVE.sol";
import { VeCVE } from "contracts/token/VeCVE.sol";

contract DisableContinuousLockTest is TestBaseVeCVE {
    function setUp() public override {
        super.setUp();

        deal(address(cve), address(this), 100e18);
        cve.approve(address(veCVE), 100e18);

        veCVE.createLock(50e18, true, rewardsData, "", 0);
    }

    function test_disableContinuousLock_fail_whenLockIndexIsInvalid(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        vm.expectRevert(VeCVE.VeCVE__InvalidLock.selector);
        veCVE.disableContinuousLock(1, rewardsData, "", 0);
    }

    function test_disableContinuousLock_fail_whenLockIsNotContinousLock(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        veCVE.createLock(100, false, rewardsData, "", 0);

        vm.expectRevert(VeCVE.VeCVE__LockTypeMismatch.selector);
        veCVE.disableContinuousLock(1, rewardsData, "", 0);
    }

    function test_disableContinuousLock_success(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        (, uint40 unlockTime) = veCVE.userLocks(address(this), 0);

        assertEq(veCVE.chainPoints(), 100e18);
        assertEq(veCVE.userPoints(address(this)), 100e18);
        assertEq(veCVE.chainUnlocksByEpoch(veCVE.currentEpoch(unlockTime)), 0);
        assertEq(
            veCVE.userUnlocksByEpoch(
                address(this),
                veCVE.currentEpoch(unlockTime)
            ),
            0
        );

        veCVE.disableContinuousLock(0, rewardsData, "", 0);

        (, unlockTime) = veCVE.userLocks(address(this), 0);

        assertEq(unlockTime, veCVE.freshLockTimestamp());
        assertEq(veCVE.chainPoints(), 50e18);
        assertEq(veCVE.userPoints(address(this)), 50e18);
        assertEq(
            veCVE.chainUnlocksByEpoch(veCVE.currentEpoch(unlockTime)),
            50e18
        );
        assertEq(
            veCVE.userUnlocksByEpoch(
                address(this),
                veCVE.currentEpoch(unlockTime)
            ),
            50e18
        );
    }
}
