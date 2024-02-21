// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseFeeAccumulator } from "../TestBaseFeeAccumulator.sol";
import { EpochRolloverData } from "contracts/interfaces/IFeeAccumulator.sol";
import { FeeAccumulator } from "contracts/architecture/FeeAccumulator.sol";

contract ExecuteEpochFeeRouterTest is TestBaseFeeAccumulator {
    EpochRolloverData data =
        EpochRolloverData({
            chainId: 42161,
            value: _ONE,
            numChainData: 1,
            epoch: 0
        });

    function test_executeEpochFeeRouter_fail_whenChainIsNotSupported() public {
        centralRegistry.addChainSupport(
            address(protocolMessagingHub),
            address(protocolMessagingHub),
            address(cve),
            42161,
            1,
            1,
            23
        );

        uint256 currentEpoch = cveLocker.currentEpoch(block.timestamp);
        uint256 nextEpoch = cveLocker.nextEpochToDeliver();

        vm.prank(address(protocolMessagingHub));

        vm.expectRevert(
            abi.encodeWithSelector(
                FeeAccumulator.FeeAccumulator__CurrentEpochError.selector,
                currentEpoch,
                nextEpoch
            )
        );
        feeAccumulator.executeEpochFeeRouter(42161);
    }

    function test_executeEpochFeeRouter_success_whenChainIsNotSupported()
        public
    {
        skip(2 weeks);

        vm.expectRevert();
        feeAccumulator.crossChainLockData(0);

        vm.prank(address(protocolMessagingHub));
        feeAccumulator.executeEpochFeeRouter(42161);

        vm.expectRevert();
        feeAccumulator.crossChainLockData(0);
    }

    function test_executeEpochFeeRouter_success_whenChainIsSupported() public {
        skip(2 weeks);

        deal(address(protocolMessagingHub), _ONE);
        deal(address(feeAccumulator), _ONE);
        deal(_USDC_ADDRESS, address(feeAccumulator), 10e6);

        centralRegistry.addChainSupport(
            address(protocolMessagingHub),
            address(protocolMessagingHub),
            address(cve),
            42161,
            1,
            1,
            23
        );

        uint256 nextEpoch = cveLocker.nextEpochToDeliver();

        vm.prank(address(protocolMessagingHub));
        feeAccumulator.receiveCrossChainLockData(data);

        (uint224 lockAmount, uint16 epoch, uint16 chainId) = feeAccumulator
            .crossChainLockData(0);

        assertEq(lockAmount, _ONE);
        assertEq(chainId, 42161);
        assertEq(epoch, nextEpoch);

        vm.prank(address(protocolMessagingHub));
        feeAccumulator.executeEpochFeeRouter(42161);

        vm.expectRevert();
        feeAccumulator.crossChainLockData(0);

        assertEq(usdc.balanceOf(address(feeAccumulator)), 0);
    }
}
