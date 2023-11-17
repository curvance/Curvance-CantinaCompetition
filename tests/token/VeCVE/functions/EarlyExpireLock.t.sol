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

    function test_earlyExpireLock_fail_whenLockIndexExceeds(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        vm.expectRevert(VeCVE.VeCVE__InvalidLock.selector);
        veCVE.earlyExpireLock(1, rewardsData, "", 0);
    }

    function test_earlyExpireLock_fail_whenEarlyUnlockIsDisabled(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        vm.expectRevert(VeCVE.VeCVE__InvalidLock.selector);
        veCVE.earlyExpireLock(0, rewardsData, "", 0);
    }

    function test_earlyExpireLock_success(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        centralRegistry.setEarlyUnlockPenaltyMultiplier(3000);

        uint256 penaltyAmount = veCVE.getUnlockPenalty(address(this), 0);

        vm.expectEmit(true, true, true, true, address(veCVE));
        emit UnlockedWithPenalty(address(this), 30e18, penaltyAmount);

        veCVE.earlyExpireLock(0, rewardsData, "", 0);
    }
}
