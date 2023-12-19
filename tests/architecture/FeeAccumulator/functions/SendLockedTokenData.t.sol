// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseFeeAccumulator } from "../TestBaseFeeAccumulator.sol";
import { FeeAccumulator } from "contracts/architecture/FeeAccumulator.sol";

contract SendLockedTokenDataTest is TestBaseFeeAccumulator {
    function test_sendLockedTokenData_fail_whenCallerIsNotAuthorized() public {
        vm.expectRevert(FeeAccumulator.FeeAccumulator__Unauthorized.selector);
        feeAccumulator.sendLockedTokenData(
            42161,
            address(protocolMessagingHub)
        );
    }

    function test_sendLockedTokenData_fail_whenChainIsNotSupported() public {
        vm.expectRevert(
            FeeAccumulator.FeeAccumulator__ChainIsNotSupported.selector
        );

        vm.prank(harvester);
        feeAccumulator.sendLockedTokenData(
            42161,
            address(protocolMessagingHub)
        );
    }

    function test_sendLockedTokenData_fail_whenAddressIsNotCVEAddress()
        public
    {
        centralRegistry.addChainSupport(
            address(this),
            address(1),
            address(cve),
            23,
            1,
            1,
            42161
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
        feeAccumulator.sendLockedTokenData(23, address(protocolMessagingHub));
    }

    function test_sendLockedTokenData_fail_whenHasNoEnoughNativeAssetForGas()
        public
    {
        centralRegistry.addChainSupport(
            address(this),
            address(protocolMessagingHub),
            address(cve),
            23,
            1,
            1,
            42161
        );

        vm.expectRevert();

        vm.prank(harvester);
        feeAccumulator.sendLockedTokenData(23, address(protocolMessagingHub));
    }
}
