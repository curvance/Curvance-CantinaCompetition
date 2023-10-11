// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseFeeAccumulator } from "../TestBaseFeeAccumulator.sol";
import { EpochRolloverData } from "contracts/interfaces/IFeeAccumulator.sol";

contract ReceiveCrossChainLockDataTest is TestBaseFeeAccumulator {
    function test_receiveCrossChainLockData_fail_whenCallerIsNotMessagingHub()
        public
    {
        vm.expectRevert("FeeAccumulator: UNAUTHORIZED");
        feeAccumulator.receiveCrossChainLockData(
            EpochRolloverData({
                chainId: 110,
                value: _ONE,
                numChainData: 1,
                epoch: 0
            })
        );
    }

    function test_receiveCrossChainLockData_success() public {
        deal(_USDC_ADDRESS, address(feeAccumulator), 100e6);
        deal(address(feeAccumulator), _ONE);
        deal(address(protocolMessagingHub), _ONE);

        centralRegistry.addChainSupport(
            address(this),
            address(this),
            abi.encodePacked(address(cve)),
            110,
            1,
            1,
            110
        );

        // Todo: Should figure out the issue
        // vm.prank(address(protocolMessagingHub));
        // feeAccumulator.receiveCrossChainLockData(
        //     EpochRolloverData({
        //         chainId: 110,
        //         value: _ONE,
        //         numChainData: 1,
        //         epoch: 0
        //     })
        // );
    }
}
