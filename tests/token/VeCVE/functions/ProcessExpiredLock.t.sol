// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseVeCVE } from "../TestBaseVeCVE.sol";
import { VeCVE } from "contracts/token/VeCVE.sol";

contract ProcessExpiredLockTest is TestBaseVeCVE {
    event Unlocked(address indexed user, uint256 amount);

    function setUp() public override {
        super.setUp();

        deal(address(cve), address(this), 100e18);
        cve.approve(address(veCVE), 100e18);

        veCVE.lock(30e18, false, address(this), rewardsData, "", 0);
    }

    function test_processExpiredLock_fail_whenLockIndexExceeds(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        vm.expectRevert(VeCVE.VeCVE_InvalidLock.selector);
        veCVE.processExpiredLock(
            1,
            false,
            false,
            address(this),
            rewardsData,
            "",
            0
        );
    }

    function test_processExpiredLock_fail_whenLockIsNotExpired(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        vm.expectRevert("VeCVE: lock has not expired");
        veCVE.processExpiredLock(
            0,
            false,
            false,
            address(this),
            rewardsData,
            "",
            0
        );
    }

    function test_processExpiredLock_success_withContinuousLock(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        (, uint40 unlockTime) = veCVE.userLocks(address(this), 0);
        vm.warp(unlockTime);

        vm.expectEmit(true, true, true, true, address(veCVE));
        emit Unlocked(address(this), 30e18);

        veCVE.processExpiredLock(
            0,
            false,
            true,
            address(this),
            rewardsData,
            "",
            0
        );
    }

    function test_processExpiredLock_success_withDiscontinuousLock(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        (, uint40 unlockTime) = veCVE.userLocks(address(this), 0);
        vm.warp(unlockTime);

        vm.expectEmit(true, true, true, true, address(veCVE));
        emit Unlocked(address(this), 30e18);

        veCVE.processExpiredLock(
            0,
            false,
            false,
            address(this),
            rewardsData,
            "",
            0
        );
    }
}
