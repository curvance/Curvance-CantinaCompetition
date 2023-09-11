// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseCVELocker } from "../TestBaseCVELocker.sol";
import { CVELocker } from "contracts/architecture/CVELocker.sol";

contract RecordEpochRewardsTest is TestBaseCVELocker {
    uint256 nextEpochToDeliver;

    function setUp() public override {
        super.setUp();

        nextEpochToDeliver = cveLocker.nextEpochToDeliver();
    }

    function test_recordEpochRewards_fail_whenCallerIsNotFeeAccumulator()
        public
    {
        vm.expectRevert("CVELocker: UNAUTHORIZED");
        cveLocker.recordEpochRewards(nextEpochToDeliver, _ONE);
    }

    function test_recordEpochRewards_fail_whenEpochIsNotNextEpochToDeliver()
        public
    {
        vm.prank(centralRegistry.feeAccumulator());

        vm.expectRevert(
            CVELocker.CVELocker__WrongEpochRewardSubmission.selector
        );
        cveLocker.recordEpochRewards(nextEpochToDeliver + 1, _ONE);
    }

    function test_recordEpochRewards_success() public {
        assertEq(cveLocker.epochRewardsPerCVE(nextEpochToDeliver), 0);

        vm.prank(centralRegistry.feeAccumulator());
        cveLocker.recordEpochRewards(nextEpochToDeliver, _ONE);

        assertEq(cveLocker.epochRewardsPerCVE(nextEpochToDeliver), _ONE);
        assertEq(cveLocker.nextEpochToDeliver(), nextEpochToDeliver + 1);
    }
}
