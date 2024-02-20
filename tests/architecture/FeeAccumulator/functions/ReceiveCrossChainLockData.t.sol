// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseFeeAccumulator } from "../TestBaseFeeAccumulator.sol";
import { EpochRolloverData } from "contracts/interfaces/IFeeAccumulator.sol";
import { FeeAccumulator } from "contracts/architecture/FeeAccumulator.sol";
import { ICVELocker } from "contracts/interfaces/ICVELocker.sol";

contract ReceiveCrossChainLockDataTest is TestBaseFeeAccumulator {
    EpochRolloverData data =
        EpochRolloverData({
            chainId: 42161,
            value: _ONE,
            numChainData: 1,
            epoch: 0
        });

    function test_receiveCrossChainLockData_fail_whenCallerIsNotMessagingHub()
        public
    {
        vm.expectRevert(FeeAccumulator.FeeAccumulator__Unauthorized.selector);
        feeAccumulator.receiveCrossChainLockData(data);
    }

    function test_receiveCrossChainLockData_success_whenChainIsNotSupported()
        public
    {
        vm.expectRevert();
        feeAccumulator.crossChainLockData(0);

        vm.prank(address(protocolMessagingHub));
        feeAccumulator.receiveCrossChainLockData(data);

        vm.expectRevert();
        feeAccumulator.crossChainLockData(0);
    }

    function test_receiveCrossChainLockData_success_whenChainIsSupported()
        public
    {
        centralRegistry.addChainSupport(
            address(this),
            address(this),
            address(cve),
            42161,
            1,
            1,
            23
        );
        centralRegistry.addChainSupport(
            address(this),
            address(this),
            address(cve),
            137,
            1,
            1,
            5
        );

        vm.expectRevert();
        feeAccumulator.crossChainLockData(0);

        uint256 nextEpoch = ICVELocker(centralRegistry.cveLocker())
            .nextEpochToDeliver();

        vm.prank(address(protocolMessagingHub));
        feeAccumulator.receiveCrossChainLockData(data);

        (uint224 lockAmount, uint16 epoch, uint16 chainId) = feeAccumulator
            .crossChainLockData(0);

        assertEq(lockAmount, _ONE);
        assertEq(chainId, 42161);
        assertEq(epoch, nextEpoch);

        vm.prank(address(protocolMessagingHub));
        feeAccumulator.receiveCrossChainLockData(data);

        (lockAmount, epoch, chainId) = feeAccumulator.crossChainLockData(0);

        assertEq(lockAmount, _ONE);
        assertEq(chainId, 42161);
        assertEq(epoch, nextEpoch);

        vm.expectRevert();
        feeAccumulator.crossChainLockData(1);

        data.chainId = 137;

        vm.prank(address(protocolMessagingHub));
        feeAccumulator.receiveCrossChainLockData(data);

        (lockAmount, epoch, chainId) = feeAccumulator.crossChainLockData(1);

        assertEq(lockAmount, _ONE);
        assertEq(chainId, 137);
        assertEq(epoch, nextEpoch);

        vm.expectRevert();
        feeAccumulator.crossChainLockData(2);
    }
}
