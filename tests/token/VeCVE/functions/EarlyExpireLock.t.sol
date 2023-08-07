// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

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

        veCVE.lock(30e18, false, address(this), rewardsData, "", 0);
    }

    function test_earlyExpireLock_fail_whenLockIndexExceeds(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        vm.expectRevert(VeCVE.VeCVE_InvalidLock.selector);
        veCVE.earlyExpireLock(
            address(this),
            1,
            address(this),
            rewardsData,
            "",
            0
        );
    }

    function test_earlyExpireLock_fail_whenEarlyUnlockIsDisabled(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        vm.expectRevert("VeCVE: early unlocks disabled");
        veCVE.earlyExpireLock(
            address(this),
            0,
            address(this),
            rewardsData,
            "",
            0
        );
    }

    function test_earlyExpireLock_success(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        centralRegistry.setEarlyUnlockPenaltyValue(3000);

        uint256 panaltyAmount = (30e18 * 3000) / veCVE.DENOMINATOR();

        vm.expectEmit(true, true, true, true, address(veCVE));
        emit UnlockedWithPenalty(address(this), 30e18, panaltyAmount);

        veCVE.earlyExpireLock(
            address(this),
            0,
            address(this),
            rewardsData,
            "",
            0
        );
    }
}
