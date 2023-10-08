// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseVeCVE } from "../TestBaseVeCVE.sol";
import { VeCVE } from "contracts/token/VeCVE.sol";

contract CombineLocksTest is TestBaseVeCVE {
    uint256[] public lockIndexes;

    function setUp() public override {
        super.setUp();

        deal(address(cve), address(this), 100e18);
        cve.approve(address(veCVE), 100e18);

        veCVE.lock(30e18, false, address(this), rewardsData, "", 0);
        veCVE.lock(30e18, true, address(this), rewardsData, "", 0);
        veCVE.lock(30e18, false, address(this), rewardsData, "", 0);

        lockIndexes.push(0);
        lockIndexes.push(1);
        lockIndexes.push(2);
    }

    function test_combineLocks_fail_whenCombineOneLock(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        lockIndexes.pop();
        lockIndexes.pop();

        vm.expectRevert(VeCVE.VeCVE__InvalidLock.selector);
        veCVE.combineLocks(
            lockIndexes,
            false,
            address(this),
            rewardsData,
            "",
            0
        );
    }

    function test_combineLocks_fail_whenLockIndexesLengthExceeds(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        lockIndexes.push(3);

        vm.expectRevert(VeCVE.VeCVE__InvalidLock.selector);
        veCVE.combineLocks(
            lockIndexes,
            false,
            address(this),
            rewardsData,
            "",
            0
        );
    }

    function test_combineLocks_fail_whenLockIndexesAreNotSorted(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        lockIndexes[1] = 2;
        lockIndexes[2] = 1;

        vm.expectRevert(VeCVE.VeCVE__ParametersareInvalid.selector);
        veCVE.combineLocks(
            lockIndexes,
            false,
            address(this),
            rewardsData,
            "",
            0
        );
    }

    function test_combineLocks_success_withContinuousLock(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        (uint256 lockAmount, uint40 unlockTime) = veCVE.userLocks(
            address(this),
            2
        );

        assertEq(veCVE.chainTokenPoints(), 120e18);
        assertEq(veCVE.userTokenPoints(address(this)), 120e18);
        assertEq(
            veCVE.chainUnlocksByEpoch(veCVE.currentEpoch(unlockTime)),
            60e18
        );
        assertEq(
            veCVE.userTokenUnlocksByEpoch(
                address(this),
                veCVE.currentEpoch(unlockTime)
            ),
            60e18
        );

        veCVE.combineLocks(
            lockIndexes,
            true,
            address(this),
            rewardsData,
            "",
            0
        );

        vm.expectRevert(VeCVE.VeCVE__ParametersareInvalid.selector);
        veCVE.userLocks(address(this), 1);

        (lockAmount, unlockTime) = veCVE.userLocks(address(this), 0);

        assertEq(lockAmount, 90e18);
        assertEq(unlockTime, veCVE.CONTINUOUS_LOCK_VALUE());
        assertEq(veCVE.chainTokenPoints(), 180e18);
        assertEq(veCVE.userTokenPoints(address(this)), 180e18);
        assertEq(veCVE.chainUnlocksByEpoch(veCVE.currentEpoch(unlockTime)), 0);
        assertEq(
            veCVE.userTokenUnlocksByEpoch(
                address(this),
                veCVE.currentEpoch(unlockTime)
            ),
            0
        );
    }

    function test_combineLocks_success_withDiscontinuousLock(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        (uint256 lockAmount, uint40 unlockTime) = veCVE.userLocks(
            address(this),
            2
        );

        assertEq(veCVE.chainTokenPoints(), 120e18);
        assertEq(veCVE.userTokenPoints(address(this)), 120e18);
        assertEq(
            veCVE.chainUnlocksByEpoch(veCVE.currentEpoch(unlockTime)),
            60e18
        );
        assertEq(
            veCVE.userTokenUnlocksByEpoch(
                address(this),
                veCVE.currentEpoch(unlockTime)
            ),
            60e18
        );

        veCVE.combineLocks(
            lockIndexes,
            false,
            address(this),
            rewardsData,
            "",
            0
        );

        vm.expectRevert(VeCVE.VeCVE__ParametersareInvalid.selector);
        veCVE.userLocks(address(this), 1);

        (lockAmount, unlockTime) = veCVE.userLocks(address(this), 0);

        assertEq(lockAmount, 90e18);
        assertEq(unlockTime, veCVE.freshLockTimestamp());
        assertEq(veCVE.chainTokenPoints(), 90e18);
        assertEq(veCVE.userTokenPoints(address(this)), 90e18);
        assertEq(
            veCVE.chainUnlocksByEpoch(veCVE.currentEpoch(unlockTime)),
            90e18
        );
        assertEq(
            veCVE.userTokenUnlocksByEpoch(
                address(this),
                veCVE.currentEpoch(unlockTime)
            ),
            90e18
        );
    }
}
