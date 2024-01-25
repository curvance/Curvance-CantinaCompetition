// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseVeCVE } from "../TestBaseVeCVE.sol";
import { VeCVE } from "contracts/token/VeCVE.sol";

contract DisableContinuousLockTest is TestBaseVeCVE {
    event RewardPaid(address user, address rewardToken, uint256 amount);

    function setUp() public override {
        super.setUp();

        deal(address(cve), address(this), 100e18);
        cve.approve(address(veCVE), 100e18);

        veCVE.createLock(50e18, true, rewardsData, "", 0);

        deal(_USDC_ADDRESS, address(cveLocker), 100e18);
    }

    function test_disableContinuousLock_fail_whenLockIndexIsInvalid() public {
        // no need to set rewardsData because it will not be called
        vm.expectRevert(VeCVE.VeCVE__InvalidLock.selector);
        veCVE.disableContinuousLock(1, rewardsData, "", 0);
    }

    function test_disableContinuousLock_fail_whenLockIsNotContinousLock(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        veCVE.createLock(30e18, false, rewardsData, "", 0);

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

        vm.prank(address(cveLocker.veCVE()));
        cveLocker.updateUserClaimIndex(address(this), 1);

        for (uint256 i = 0; i < 2; i++) {
            vm.prank(centralRegistry.feeAccumulator());
            cveLocker.recordEpochRewards(_ONE);
        }

        // verify that rewards are delivered
        vm.expectEmit(true, true, true, true, address(cveLocker));
        emit RewardPaid(address(this), _USDC_ADDRESS, 100e18);
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
