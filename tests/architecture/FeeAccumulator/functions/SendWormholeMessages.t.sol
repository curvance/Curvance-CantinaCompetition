// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseFeeAccumulator } from "../TestBaseFeeAccumulator.sol";
import { FeeAccumulator } from "contracts/architecture/FeeAccumulator.sol";
import { ICVELocker } from "contracts/interfaces/ICVELocker.sol";

contract FeeAccumulatorSendWormholeMessagesTest is TestBaseFeeAccumulator {
    function setUp() public override {
        super.setUp();

        centralRegistry.addChainSupport(
            address(this),
            address(protocolMessagingHub),
            address(cve),
            42161,
            1,
            1,
            23
        );
    }

    function test_feeAccumulatorSendWormholeMessages_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.expectRevert(FeeAccumulator.FeeAccumulator__Unauthorized.selector);
        feeAccumulator.sendWormholeMessages(
            42161,
            address(protocolMessagingHub)
        );
    }

    function test_feeAccumulatorSendWormholeMessages_fail_whenChainIsNotSupported()
        public
    {
        centralRegistry.removeChainSupport(address(this), 42161);

        vm.expectRevert(
            FeeAccumulator.FeeAccumulator__ChainIsNotSupported.selector
        );

        vm.prank(harvester);
        feeAccumulator.sendWormholeMessages(
            42161,
            address(protocolMessagingHub)
        );
    }

    function test_feeAccumulatorSendWormholeMessages_fail_whenAddressIsNotCVEAddress()
        public
    {
        centralRegistry.removeChainSupport(address(this), 42161);
        centralRegistry.addChainSupport(
            address(this),
            address(1),
            address(cve),
            42161,
            1,
            1,
            23
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                FeeAccumulator
                    .FeeAccumulator__ToAddressIsNotMessagingHub
                    .selector,
                address(1),
                address(protocolMessagingHub)
            )
        );

        vm.prank(harvester);
        feeAccumulator.sendWormholeMessages(
            42161,
            address(protocolMessagingHub)
        );
    }

    function test_feeAccumulatorSendWormholeMessages_fail_whenHasNoEnoughNativeAssetForGas()
        public
    {
        vm.expectRevert();

        vm.prank(harvester);
        feeAccumulator.sendWormholeMessages(
            42161,
            address(protocolMessagingHub)
        );
    }

    function test_feeAccumulatorSendWormholeMessages_success() public {
        uint256 messageFee = protocolMessagingHub.quoteWormholeFee(
            42161,
            false
        );
        deal(address(feeAccumulator), messageFee);

        uint256 nextEpoch = ICVELocker(centralRegistry.cveLocker())
            .nextEpochToDeliver();
        assertEq(feeAccumulator.lockedTokenDataSent(42161, nextEpoch), 0);

        vm.prank(harvester);
        feeAccumulator.sendWormholeMessages(
            42161,
            address(protocolMessagingHub)
        );

        assertEq(feeAccumulator.lockedTokenDataSent(42161, nextEpoch), 2);

        vm.prank(harvester);
        feeAccumulator.sendWormholeMessages(
            42161,
            address(protocolMessagingHub)
        );
    }
}
