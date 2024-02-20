// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseCTokenCompoundingWithExitFee } from "../TestBaseCTokenCompoundingWithExitFee.sol";
import { CTokenBase } from "contracts/market/collateral/CTokenBase.sol";
import { SafeTransferLib } from "contracts/libraries/external/SafeTransferLib.sol";

contract CTokenCompoundingWithExitFeeStartMarketTest is
    TestBaseCTokenCompoundingWithExitFee
{
    function test_cTokenCompoundingWithExitFeeStartMarket_fail_whenCallerIsNotMarketManager()
        public
    {
        vm.expectRevert(CTokenBase.CTokenBase__Unauthorized.selector);

        cBALRETHWithExitFee.startMarket(address(0));
    }

    function test_cTokenCompoundingWithExitFeeStartMarket_fail_whenInitializerIsZeroAddress()
        public
    {
        vm.expectRevert(SafeTransferLib.TransferFromFailed.selector);

        vm.prank(address(marketManager));
        cBALRETHWithExitFee.startMarket(address(0));
    }

    function test_cTokenCompoundingWithExitFeeStartMarket_success() public {
        vm.prank(user1);
        SafeTransferLib.safeApprove(
            _BALANCER_WETH_RETH,
            address(cBALRETHWithExitFee),
            1e18
        );

        uint256 totalSupply = cBALRETHWithExitFee.totalSupply();

        vm.prank(address(marketManager));
        cBALRETHWithExitFee.startMarket(user1);

        assertEq(cBALRETHWithExitFee.totalSupply(), totalSupply + 42069);
    }
}
