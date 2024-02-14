// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseCTokenCompounding } from "../TestBaseCTokenCompounding.sol";
import { CTokenBase } from "contracts/market/collateral/CTokenBase.sol";
import { SafeTransferLib } from "contracts/libraries/external/SafeTransferLib.sol";

contract CTokenCompoundingStartMarketTest is TestBaseCTokenCompounding {
    function test_cTokenCompoundingStartMarket_fail_whenCallerIsNotMarketManager()
        public
    {
        vm.expectRevert(CTokenBase.CTokenBase__Unauthorized.selector);

        cBALRETH.startMarket(address(0));
    }

    function test_cTokenCompoundingStartMarket_fail_whenInitializerIsZeroAddress()
        public
    {
        vm.expectRevert(SafeTransferLib.TransferFromFailed.selector);

        vm.prank(address(marketManager));
        cBALRETH.startMarket(address(0));
    }

    function test_cTokenCompoundingStartMarket_success() public {
        vm.prank(user1);
        SafeTransferLib.safeApprove(
            _BALANCER_WETH_RETH,
            address(cBALRETH),
            1e18
        );

        uint256 totalSupply = cBALRETH.totalSupply();

        vm.prank(address(marketManager));
        cBALRETH.startMarket(user1);

        assertEq(cBALRETH.totalSupply(), totalSupply + 42069);
    }
}
