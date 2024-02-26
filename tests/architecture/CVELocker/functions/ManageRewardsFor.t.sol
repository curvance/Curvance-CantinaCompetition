// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseCVELocker } from "../TestBaseCVELocker.sol";
import { CVELocker } from "contracts/architecture/CVELocker.sol";
import { RewardsData } from "contracts/interfaces/ICVELocker.sol";

contract ManageRewardsForTest is TestBaseCVELocker {
    event RewardPaid(address user, address rewardToken, uint256 amount);

    RewardsData public rewardsData = RewardsData(true, false, false, false);

    function setUp() public override {
        super.setUp();

        deal(_USDC_ADDRESS, address(cveLocker), 10000e6);
    }

    function test_manageRewardsFor_fail_whenNotDelegated() public {
        vm.expectRevert(CVELocker.CVELocker__Unauthorized.selector);
        cveLocker.manageRewardsFor(user1, 0);
    }

    function test_manageRewardsFor_success() public {
        vm.startPrank(user1);

        cveLocker.setDelegateApproval(address(this), true);

        deal(address(cve), user1, 100e18);
        cve.approve(address(veCVE), 100e18);

        veCVE.createLock(100e18, false, rewardsData, "0x", 0);

        vm.stopPrank();

        vm.prank(address(veCVE));
        cveLocker.updateUserClaimIndex(user1, 1);

        for (uint256 i = 0; i < 2; i++) {
            vm.prank(centralRegistry.feeAccumulator());
            cveLocker.recordEpochRewards(1e6);
        }

        assertEq(usdc.balanceOf(address(this)), 0);

        uint256 epoch = cveLocker.epochsToClaim(user1);

        vm.expectEmit(true, true, true, true);
        emit RewardPaid(user1, _USDC_ADDRESS, 100e6);

        cveLocker.manageRewardsFor(user1, epoch);

        assertEq(usdc.balanceOf(address(this)), 100e6);
    }
}
