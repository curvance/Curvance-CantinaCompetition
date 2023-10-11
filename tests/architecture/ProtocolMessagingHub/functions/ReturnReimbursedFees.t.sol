// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseProtocolMessagingHub } from "../TestBaseProtocolMessagingHub.sol";

contract ReturnReimbursedFeesTest is TestBaseProtocolMessagingHub {
    function test_returnReimbursedFees_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.expectRevert("ProtocolMessagingHub: UNAUTHORIZED");

        vm.prank(address(1));
        protocolMessagingHub.returnReimbursedFees();
    }

    function test_returnReimbursedFees_success() public {
        deal(_USDC_ADDRESS, address(protocolMessagingHub), _ONE);

        protocolMessagingHub.returnReimbursedFees();

        assertEq(usdc.balanceOf(address(protocolMessagingHub)), 0);
        assertEq(usdc.balanceOf(address(feeAccumulator)), _ONE);
    }
}
