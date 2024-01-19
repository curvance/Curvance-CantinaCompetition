// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseOneBalanceFeeManager } from "../TestBaseOneBalanceFeeManager.sol";
import { OneBalanceFeeManager } from "contracts/architecture/OneBalanceFeeManager.sol";

contract DepositOneBalanceFeeTest is TestBaseOneBalanceFeeManager {
    function test_depositOneBalanceFee_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.prank(user1);

        vm.expectRevert(
            OneBalanceFeeManager.OneBalanceFeeManager__Unauthorized.selector
        );
        oneBalanceFeeManager.depositOneBalanceFee();
    }

    function test_depositOneBalanceFee_success() public {
        deal(address(oneBalanceFeeManager), _ONE);
        deal(_USDC_ADDRESS, address(oneBalanceFeeManager), 100e6);

        assertEq(usdc.balanceOf(address(oneBalanceFeeManager)), 100e6);

        oneBalanceFeeManager.depositOneBalanceFee();

        assertEq(usdc.balanceOf(address(oneBalanceFeeManager)), 0);
    }
}
