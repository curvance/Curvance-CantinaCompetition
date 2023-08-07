// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseVeCVE } from "../TestBaseVeCVE.sol";
import { VeCVE } from "contracts/token/VeCVE.sol";

contract DisableContinuousLockTest is TestBaseVeCVE {
    function setUp() public override {
        super.setUp();

        deal(address(cve), address(this), 100e18);
        cve.approve(address(veCVE), 100e18);

        veCVE.lock(50e18, true, address(this), rewardsData, "", 0);
    }

    function test_disableContinuousLock_fail_whenLockIndexIsInvalid(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        vm.expectRevert(VeCVE.VeCVE_InvalidLock.selector);
        veCVE.disableContinuousLock(1, address(this), rewardsData, "", 0);
    }

    function test_disableContinuousLock_fail_whenLockIsNotContinousLock(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        veCVE.lock(100, false, address(this), rewardsData, "", 0);

        vm.expectRevert(VeCVE.VeCVE_NotContinuousLock.selector);
        veCVE.disableContinuousLock(1, address(this), rewardsData, "", 0);
    }

    function test_disableContinuousLock_success(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        (, uint40 unlockTime) = veCVE.userLocks(address(this), 0);

        assertEq(veCVE.chainTokenPoints(), 100e18);
        assertEq(veCVE.userTokenPoints(address(this)), 100e18);
        assertEq(veCVE.chainUnlocksByEpoch(veCVE.currentEpoch(unlockTime)), 0);
        assertEq(
            veCVE.userTokenUnlocksByEpoch(
                address(this),
                veCVE.currentEpoch(unlockTime)
            ),
            0
        );

        veCVE.disableContinuousLock(0, address(this), rewardsData, "", 0);

        (, unlockTime) = veCVE.userLocks(address(this), 0);

        assertEq(unlockTime, veCVE.freshLockTimestamp());
        assertEq(veCVE.chainTokenPoints(), 50e18);
        assertEq(veCVE.userTokenPoints(address(this)), 50e18);
        assertEq(
            veCVE.chainUnlocksByEpoch(veCVE.currentEpoch(unlockTime)),
            50e18
        );
        assertEq(
            veCVE.userTokenUnlocksByEpoch(
                address(this),
                veCVE.currentEpoch(unlockTime)
            ),
            50e18
        );
    }
}
