// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseDToken } from "../TestBaseDToken.sol";
import { SafeTransferLib } from "contracts/libraries/external/SafeTransferLib.sol";
import { DToken } from "contracts/market/collateral/DToken.sol";

contract DTokenStartMarketTest is TestBaseDToken {
    function test_dTokenStartMarket_fail_whenCallerIsNotMarketManager() public {
        vm.expectRevert(DToken.DToken__Unauthorized.selector);

        dUSDC.startMarket(address(0));
    }

    function test_dTokenStartMarket_fail_whenInitializerIsZeroAddress()
        public
    {
        vm.expectRevert(SafeTransferLib.TransferFromFailed.selector);

        vm.prank(address(marketManager));
        dUSDC.startMarket(address(0));
    }

    function test_dTokenStartMarket_success() public {
        vm.prank(user1);
        SafeTransferLib.safeApprove(_USDC_ADDRESS, address(dUSDC), 1e18);

        uint256 totalSupply = dUSDC.totalSupply();

        vm.prank(address(marketManager));
        dUSDC.startMarket(user1);

        assertEq(dUSDC.totalSupply(), totalSupply + 42069);
    }
}
