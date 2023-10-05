// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseCToken } from "../TestBaseCToken.sol";
import { BasePositionVault } from "contracts/deposits/adaptors/BasePositionVault.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";
import { CToken } from "contracts/market/collateral/CToken.sol";

contract CTokenStartMarketTest is TestBaseCToken {
    function test_cTokenStartMarket_fail_whenCallerIsNotLendtroller() public {
        vm.expectRevert(CToken.CToken__UnauthorizedCaller.selector);

        cBALRETH.startMarket(address(0));
    }

    function test_cTokenStartMarket_fail_whenInitializerIsZeroAddress()
        public
    {
        vm.expectRevert(SafeTransferLib.TransferFromFailed.selector);

        vm.prank(address(lendtroller));
        cBALRETH.startMarket(address(0));
    }

    function test_cTokenStartMarket_fail_whenVaultIsNotActive() public {
        vault.initiateShutdown();

        vm.prank(user1);
        SafeTransferLib.safeApprove(
            _BALANCER_WETH_RETH,
            address(cBALRETH),
            1e18
        );

        vm.expectRevert(
            BasePositionVault.BasePositionVault__VaultNotActive.selector
        );

        vm.prank(address(lendtroller));
        cBALRETH.startMarket(user1);
    }

    function test_cTokenStartMarket_success() public {
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
