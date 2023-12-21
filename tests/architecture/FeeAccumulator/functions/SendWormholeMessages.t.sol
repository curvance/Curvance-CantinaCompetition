// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseFeeAccumulator } from "../TestBaseFeeAccumulator.sol";
import { FeeAccumulator } from "contracts/architecture/FeeAccumulator.sol";

contract SendWormholeMessagesTest is TestBaseFeeAccumulator {
    function test_sendWormholeMessages_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.expectRevert(FeeAccumulator.FeeAccumulator__Unauthorized.selector);
        feeAccumulator.sendWormholeMessages(
            42161,
            address(protocolMessagingHub)
        );
    }

    function test_sendWormholeMessages_fail_whenChainIsNotSupported() public {
        vm.expectRevert(
            FeeAccumulator.FeeAccumulator__ChainIsNotSupported.selector
        );

        vm.prank(harvester);
        feeAccumulator.sendWormholeMessages(
            42161,
            address(protocolMessagingHub)
        );
    }

    function test_sendWormholeMessages_fail_whenAddressIsNotCVEAddress()
        public
    {
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
        feeAccumulator.sendWormholeMessages(23, address(protocolMessagingHub));
    }

    function test_sendWormholeMessages_fail_whenHasNoEnoughNativeAssetForGas()
        public
    {
        centralRegistry.addChainSupport(
            address(this),
            address(protocolMessagingHub),
            address(cve),
            42161,
            1,
            1,
            23
        );

        vm.expectRevert();

        vm.prank(harvester);
        feeAccumulator.sendWormholeMessages(23, address(protocolMessagingHub));
    }
}
