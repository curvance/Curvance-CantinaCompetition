// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseVeCVE } from "../TestBaseVeCVE.sol";
import { VeCVE } from "contracts/token/VeCVE.sol";
import "forge-std/console.sol";

contract CombineAllLocksTest is TestBaseVeCVE {

    uint256 internal constant _INITIAL_AMOUNT = 30e18;

    function setUp() public override {
        super.setUp();

        deal(address(cve), address(this), _INITIAL_AMOUNT);
        cve.approve(address(veCVE), _INITIAL_AMOUNT);

        veCVE.createLock(_INITIAL_AMOUNT, false, rewardsData, "", 0);
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
        bool isFreshLockContinuous,
        uint256 amount
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        amount = bound(amount, _MIN_FUZZ_AMOUNT, _MAX_FUZZ_AMOUNT - _INITIAL_AMOUNT);
        deal(address(cve), address(this), amount);
        cve.approve(address(veCVE), amount);

        veCVE.createLock(amount, true, rewardsData, "", 0);

        (uint256 lockAmount, uint40 unlockTime) = veCVE.userLocks(
            address(this),
            1
        );

        assertEq(veCVE.chainPoints(), _INITIAL_AMOUNT + amount * 2);
        assertEq(veCVE.userPoints(address(this)), _INITIAL_AMOUNT + amount * 2);
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

        assertEq(lockAmount, _INITIAL_AMOUNT + amount);
        assertEq(unlockTime, veCVE.CONTINUOUS_LOCK_VALUE());
        assertEq(veCVE.chainPoints(), (_INITIAL_AMOUNT + amount) * 2);
        assertEq(veCVE.userPoints(address(this)), (30e18 + amount) * 2);
        assertEq(veCVE.chainUnlocksByEpoch(veCVE.currentEpoch(unlockTime)), 0);
        assertEq(
            veCVE.userUnlocksByEpoch(
                address(this),
                veCVE.currentEpoch(unlockTime)
            ),
            0
        );
    }

    function test_combineAllLocks_all_continuous_to_continuous_lock(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        veCVE.extendLock(0, true, rewardsData, "", 0);
        veCVE.createLock(1000000000000013658, true, rewardsData, "", 0);
        veCVE.createLock(1524395970892188412, true, rewardsData, "", 0);
        uint256 preCombine = (veCVE.userPoints(address(this)));

        veCVE.combineAllLocks(true, rewardsData, "", 0);

        uint256 postCombine = (veCVE.userPoints(address(this)));
        assertEq(preCombine, postCombine);
    }

    function test_combineAllLocks_some_continuous_to_continuous_lock(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        veCVE.createLock(1000000000000013658, true, rewardsData, "", 0);
        veCVE.createLock(1524395970892188412, false, rewardsData, "", 31449600);
        uint256 preCombine = (veCVE.userPoints(address(this)));

        veCVE.combineAllLocks(true, rewardsData, "", 0);

        uint256 postCombine = (veCVE.userPoints(address(this)));
        assertLt(preCombine, postCombine);
    }

    function test_combineAllLocks_success_withDiscontinuousLock(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous,
        uint256 amount
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        amount = bound(amount, _MIN_FUZZ_AMOUNT, _MAX_FUZZ_AMOUNT - _INITIAL_AMOUNT);
        deal(address(cve), address(this), amount);
        cve.approve(address(veCVE), amount);

        veCVE.createLock(amount, true, rewardsData, "", 0);

        (uint256 lockAmount, uint40 unlockTime) = veCVE.userLocks(
            address(this),
            1
        );

        assertEq(veCVE.chainPoints(), _INITIAL_AMOUNT + amount * 2);
        assertEq(veCVE.userPoints(address(this)), _INITIAL_AMOUNT + amount * 2);
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

        assertEq(lockAmount, _INITIAL_AMOUNT + amount);
        assertEq(unlockTime, veCVE.freshLockTimestamp());
        assertEq(veCVE.chainPoints(), _INITIAL_AMOUNT + amount);
        assertEq(veCVE.userPoints(address(this)), _INITIAL_AMOUNT + amount);
        assertEq(
            veCVE.chainUnlocksByEpoch(veCVE.currentEpoch(unlockTime)),
            _INITIAL_AMOUNT + amount
        );
        assertEq(
            veCVE.userUnlocksByEpoch(
                address(this),
                veCVE.currentEpoch(unlockTime)
            ),
            _INITIAL_AMOUNT + amount
        );
    }
}
