// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseOneBalanceFeeManager } from "../TestBaseOneBalanceFeeManager.sol";
import { OneBalanceFeeManager } from "contracts/architecture/OneBalanceFeeManager.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract SetOneBalanceAddressTest is TestBaseOneBalanceFeeManager {
    function test_setOneBalanceAddress_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.chainId(137);
        vm.prank(user1);

        vm.expectRevert(
            OneBalanceFeeManager.OneBalanceFeeManager__Unauthorized.selector
        );
        oneBalanceFeeManager.setOneBalanceAddress(address(1));
    }

    function test_setOneBalanceAddress_success() public {
        vm.chainId(137);

        oneBalanceFeeManager = new OneBalanceFeeManager(
            ICentralRegistry(address(centralRegistry)),
            _GELATO_ONE_BALANCE,
            address(1)
        );

        address oldOneBalance = address(
            oneBalanceFeeManager.gelatoOneBalance()
        );
        address newOneBalance = makeAddr("NewOneBalance");

        assertNotEq(
            usdc.allowance(address(oneBalanceFeeManager), oldOneBalance),
            0
        );
        assertEq(
            usdc.allowance(address(oneBalanceFeeManager), newOneBalance),
            0
        );

        oneBalanceFeeManager.setOneBalanceAddress(newOneBalance);

        assertEq(
            address(oneBalanceFeeManager.gelatoOneBalance()),
            newOneBalance
        );
        assertEq(
            usdc.allowance(address(oneBalanceFeeManager), oldOneBalance),
            0
        );
        assertEq(
            usdc.allowance(address(oneBalanceFeeManager), newOneBalance),
            type(uint256).max
        );
    }
}
