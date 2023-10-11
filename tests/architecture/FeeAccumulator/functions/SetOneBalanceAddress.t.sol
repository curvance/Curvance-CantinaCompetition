// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseFeeAccumulator } from "../TestBaseFeeAccumulator.sol";

contract SetOneBalanceAddressTest is TestBaseFeeAccumulator {
    function test_setOneBalanceAddress_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.prank(user1);

        vm.expectRevert("FeeAccumulator: UNAUTHORIZED");
        feeAccumulator.setOneBalanceAddress(address(1));
    }

    function test_setOneBalanceAddress_success() public {
        address oldOneBalance = address(feeAccumulator.gelatoOneBalance());
        address newOneBalance = makeAddr("NewOneBalance");

        assertNotEq(usdc.allowance(address(feeAccumulator), oldOneBalance), 0);
        assertEq(usdc.allowance(address(feeAccumulator), newOneBalance), 0);

        feeAccumulator.setOneBalanceAddress(newOneBalance);

        assertEq(address(feeAccumulator.gelatoOneBalance()), newOneBalance);
        assertEq(usdc.allowance(address(feeAccumulator), oldOneBalance), 0);
        assertEq(
            usdc.allowance(address(feeAccumulator), newOneBalance),
            type(uint256).max
        );
    }
}
