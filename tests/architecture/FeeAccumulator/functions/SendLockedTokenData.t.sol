// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseFeeAccumulator } from "../TestBaseFeeAccumulator.sol";
import { FeeAccumulator } from "contracts/architecture/FeeAccumulator.sol";

contract SendLockedTokenDataTest is TestBaseFeeAccumulator {
    function test_sendLockedTokenData_fail_whenCallerIsNotAuthorized() public {
        vm.expectRevert(FeeAccumulator.FeeAccumulator__Unauthorized.selector);
        feeAccumulator.sendLockedTokenData(42161, bytes32(bytes20(user1)));
    }

    function test_sendLockedTokenData_fail_whenChainIsNotSupported() public {
        vm.expectRevert(
            FeeAccumulator.FeeAccumulator__ConfigurationError.selector
        );

        vm.prank(harvester);
        feeAccumulator.sendLockedTokenData(42161, bytes32(bytes20(user1)));
    }

    function test_sendLockedTokenData_fail_whenAddressIsNotCVEAddress()
        public
    {
        centralRegistry.addChainSupport(
            address(this),
            address(this),
            abi.encodePacked(address(1)),
            110,
            1,
            1,
            42161
        );

        vm.expectRevert(
            FeeAccumulator.FeeAccumulator__ConfigurationError.selector
        );

        vm.prank(harvester);
        feeAccumulator.sendLockedTokenData(
            42161,
            bytes32(bytes20(address(cve)))
        );
    }

    function test_sendLockedTokenData_fail_whenHasNoEnoughNativeAssetForGas()
        public
    {
        centralRegistry.addChainSupport(
            address(this),
            address(this),
            abi.encodePacked(address(cve)),
            110,
            1,
            1,
            42161
        );

        vm.expectRevert();

        vm.prank(harvester);
        feeAccumulator.sendLockedTokenData(
            110,
            bytes32(bytes20(address(cve)))
        );
    }
}
