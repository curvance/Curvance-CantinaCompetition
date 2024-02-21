// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseVeCVE } from "../TestBaseVeCVE.sol";
import { VeCVE } from "contracts/token/VeCVE.sol";
import { RewardsData } from "contracts/interfaces/ICVELocker.sol";

contract CombineAllLocksTest is TestBaseVeCVE {
    uint256 internal constant _INITIAL_AMOUNT = 30e18;

    function setUp() public override {
        super.setUp();

        deal(address(cve), address(this), _INITIAL_AMOUNT);
        cve.approve(address(veCVE), _INITIAL_AMOUNT);
    }

    function test_combine_all_locks_to_non_continuous_terminal_one_wad()
        public
    {
        RewardsData memory emptyRewards = RewardsData(
            false,
            false,
            false,
            false
        );
        setUp();
        veCVE.createLock(1e18, false, emptyRewards, "", 0);
        // warp time
        vm.warp(block.timestamp + 29774646);
        veCVE.createLock(1e18, false, emptyRewards, "", 0);

        vm.warp(block.timestamp + 986121 + 675582 + 1000);
        veCVE.processExpiredLock(0, false, false, emptyRewards, "", 0);
        
        assertEq(veCVE.userPoints(address(this)), 2000000000000000000);
        (uint256[] memory lockAmounts, ) = veCVE.queryUserLocks(address(this));
        assertEq(lockAmounts.length, 1);

        veCVE.createLock(1000000024330411045, false, emptyRewards, "", 0);
        veCVE.combineAllLocks(false, emptyRewards, "", 0);

        assertEq(
            veCVE.userPoints(address(this)),
            veCVE.balanceOf(address(this))
        );
    }

    function test_combineAllLocks_fail_whenCombineOneLock(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        veCVE.createLock(_INITIAL_AMOUNT, false, rewardsData, "", 0);
        vm.expectRevert(VeCVE.VeCVE__InvalidLock.selector);
        veCVE.combineAllLocks(false, rewardsData, "", 0);
    }

    function test_combineAllLocks_success_withContinuousLock(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous,
        uint256 amount
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        veCVE.createLock(_INITIAL_AMOUNT, false, rewardsData, "", 0);
        amount = bound(
            amount,
            _MIN_FUZZ_AMOUNT,
            _MAX_FUZZ_AMOUNT - _INITIAL_AMOUNT
        );
        deal(address(cve), address(this), amount);
        cve.approve(address(veCVE), amount);

        veCVE.createLock(amount, true, rewardsData, "", 0);

        (uint256 lockAmount, uint40 unlockTime) = veCVE.userLocks(
            address(this),
            1
        );

        assertEq(veCVE.chainPoints(), _INITIAL_AMOUNT + amount * 2);
        assertEq(
            veCVE.userPoints(address(this)),
            _INITIAL_AMOUNT + amount * 2
        );
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

    function _deal(uint256 amount) internal {
        deal(address(cve), address(this), amount);
        cve.approve(address(veCVE), amount);
    }

    function test_combineAllLocks_all_continuous_to_continuous_lock(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        veCVE.createLock(_INITIAL_AMOUNT, false, rewardsData, "", 0);
        _deal(1000000000000013658 + 1524395970892188412);
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
        veCVE.createLock(_INITIAL_AMOUNT, false, rewardsData, "", 0);
        _deal(1000000000000013658 + 1524395970892188412);
        veCVE.createLock(1000000000000013658, true, rewardsData, "", 0);
        veCVE.createLock(
            1524395970892188412,
            false,
            rewardsData,
            "",
            31449600
        );
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
        veCVE.createLock(_INITIAL_AMOUNT, false, rewardsData, "", 0);
        amount = bound(
            amount,
            _MIN_FUZZ_AMOUNT,
            _MAX_FUZZ_AMOUNT - _INITIAL_AMOUNT
        );
        _deal(amount);

        veCVE.createLock(amount, true, rewardsData, "", 0);

        (uint256 lockAmount, uint40 unlockTime) = veCVE.userLocks(
            address(this),
            1
        );

        assertEq(veCVE.chainPoints(), _INITIAL_AMOUNT + amount * 2);
        assertEq(
            veCVE.userPoints(address(this)),
            _INITIAL_AMOUNT + amount * 2
        );
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
