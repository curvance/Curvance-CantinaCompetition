// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseVeCVE } from "../TestBaseVeCVE.sol";
import { VeCVE } from "contracts/token/VeCVE.sol";

contract EarlyExpireLockTest is TestBaseVeCVE {
    event UnlockedWithPenalty(
        address indexed user,
        uint256 amount,
        uint256 penaltyAmount
    );

    function setUp() public override {
        super.setUp();

        deal(address(cve), address(this), 100e18);
        cve.approve(address(veCVE), 100e18);

        veCVE.createLock(30e18, false, rewardsData, "", 0);
    }

    function test_earlyExpireLock_fail_whenLockIndexExceeds() public {
        // no need to set rewardsData because it will revert before
        vm.expectRevert(VeCVE.VeCVE__InvalidLock.selector);
        veCVE.earlyExpireLock(1, rewardsData, "", 0);
    }

    function test_earlyExpireLock_fail_whenEarlyUnlockIsDisabled() public {
        // no need to set rewardsData because it will revert before
        vm.expectRevert(VeCVE.VeCVE__InvalidLock.selector);
        veCVE.earlyExpireLock(0, rewardsData, "", 0);
    }

    function test_earlyExpireLock_success(
        uint16 penaltyMultiplier,
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        penaltyMultiplier = uint16(bound(penaltyMultiplier, 3000, 9000));
        centralRegistry.setEarlyUnlockPenaltyMultiplier(penaltyMultiplier);

        uint256 penaltyAmount = veCVE.getUnlockPenalty(address(this), 0);

        vm.expectEmit(true, true, true, true, address(veCVE));
        emit UnlockedWithPenalty(address(this), 30e18, penaltyAmount);

        veCVE.earlyExpireLock(0, rewardsData, "", 0);
    }

    function test_earlyExpireLock_fail_expired() public {
        // no need to set rewardsData because it will revert before
        (, uint40 unlockTime) = veCVE.userLocks(
            address(this),
            0
        );
        vm.warp(unlockTime);

        // cannot early expire expired lock
        vm.expectRevert(VeCVE.VeCVE__InvalidLock.selector);
        veCVE.earlyExpireLock(0, rewardsData, "", 0);
    }

    function test_getUnlockPenatly_expiredLock() public {
        centralRegistry.setEarlyUnlockPenaltyMultiplier(3000);
        (, uint40 unlockTime) = veCVE.userLocks(
            address(this),
            0
        );
        vm.warp(unlockTime);

        veCVE.getUnlockPenalty(address(this), 0);
    }

    function test_getUnlockPenalty_penaltyZero() public {
        // unlock penalty is 0 by default
        veCVE.getUnlockPenalty(address(this), 0);
    }

    function test_getUnlockPenalty_fail_invalidIndex() public {
        vm.expectRevert(VeCVE.VeCVE__InvalidLock.selector);
        veCVE.getUnlockPenalty(address(this), 111);
    }
}
