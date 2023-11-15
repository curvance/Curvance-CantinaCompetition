// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseCTokenCompoundingBase } from "../TestBaseCTokenCompoundingBase.sol";
import { CTokenCompoundingBase } from "contracts/market/collateral/CTokenCompoundingBase.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";

contract CTokenCompoundingBase_StartMarketTest is TestBaseCTokenCompoundingBase_ {
    function test_CTokenCompoundingBase_StartMarket_fail_whenCallerIsNotLendtroller() public {
        vm.expectRevert(CTokenCompoundingBase.CTokenCompoundingBase__Unauthorized.selector);

        cBALRETH.startMarket(address(0));
    }

    function test_CTokenCompoundingBase_StartMarket_fail_whenInitializerIsZeroAddress()
        public
    {
        vm.expectRevert(SafeTransferLib.TransferFromFailed.selector);

        vm.prank(address(lendtroller));
        cBALRETH.startMarket(address(0));
    }

    function test_CTokenCompoundingBase_StartMarket_fail_whenVaultIsNotActive() public {
        vault.initiateShutdown();

        vm.prank(user1);
        SafeTransferLib.safeApprove(
            _BALANCER_WETH_RETH,
            address(cBALRETH),
            1e18
        );

        vm.expectRevert(
            CTokenCompoundingBase.CTokenCompoundingBase__VaultNotActive.selector
        );

        vm.prank(address(lendtroller));
        cBALRETH.startMarket(user1);
    }

    function test_CTokenCompoundingBase_StartMarket_success() public {
        vm.prank(user1);
        SafeTransferLib.safeApprove(
            _BALANCER_WETH_RETH,
            address(cBALRETH),
            1e18
        );

        uint256 totalSupply = cBALRETH.totalSupply();

        vm.prank(address(lendtroller));
        cBALRETH.startMarket(user1);

        assertEq(cBALRETH.totalSupply(), totalSupply + 42069);
    }
}
