// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseOneBalanceFeeManager } from "../TestBaseOneBalanceFeeManager.sol";
import { OneBalanceFeeManager } from "contracts/architecture/OneBalanceFeeManager.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";

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

    function test_depositOneBalanceFee_success_notOnPolygon() public {
        deal(address(oneBalanceFeeManager), _ONE);
        deal(_USDC_ADDRESS, address(oneBalanceFeeManager), 100e6);

        assertEq(usdc.balanceOf(address(oneBalanceFeeManager)), 100e6);

        oneBalanceFeeManager.depositOneBalanceFee();

        assertEq(usdc.balanceOf(address(oneBalanceFeeManager)), 0);
    }

    function test_depositOneBalanceFee_success_onPolygon() public {
        _fork("ETH_NODE_URI_POLYGON");

        _USDC_ADDRESS = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;

        usdc = IERC20(_USDC_ADDRESS);

        _deployBaseContracts();

        deal(address(oneBalanceFeeManager), _ONE);
        deal(_USDC_ADDRESS, address(oneBalanceFeeManager), 100e6);

        uint256 balance = usdc.balanceOf(_GELATO_ONE_BALANCE);

        assertEq(usdc.balanceOf(address(oneBalanceFeeManager)), 100e6);

        oneBalanceFeeManager.depositOneBalanceFee();

        assertEq(usdc.balanceOf(address(oneBalanceFeeManager)), 0);
        assertEq(usdc.balanceOf(_GELATO_ONE_BALANCE), balance + 100e6);
    }
}
