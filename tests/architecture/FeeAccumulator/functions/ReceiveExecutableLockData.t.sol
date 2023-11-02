// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseFeeAccumulator } from "../TestBaseFeeAccumulator.sol";
import { FeeAccumulator } from "contracts/architecture/FeeAccumulator.sol";

contract ReceiveExecutableLockDataTest is TestBaseFeeAccumulator {
    function test_receiveExecutableLockData_fail_whenCallerIsNotMessagingHub()
        public
    {
        vm.expectRevert(FeeAccumulator.FeeAccumulator__Unauthorized.selector);
        feeAccumulator.receiveExecutableLockData(_ONE);
    }

    function test_receiveExecutableLockData_success() public {
        uint256 nextEpochToDeliver = cveLocker.nextEpochToDeliver();

        assertEq(cveLocker.epochRewardsPerCVE(nextEpochToDeliver), 0);

        vm.prank(address(protocolMessagingHub));
        feeAccumulator.receiveExecutableLockData(_ONE);

        assertEq(cveLocker.epochRewardsPerCVE(nextEpochToDeliver), _ONE);
        assertEq(cveLocker.nextEpochToDeliver(), nextEpochToDeliver + 1);
    }
}
