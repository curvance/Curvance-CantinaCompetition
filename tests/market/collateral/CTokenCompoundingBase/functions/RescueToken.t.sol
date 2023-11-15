// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseCTokenCompoundingBase } from "../TestBaseCTokenCompoundingBase.sol";
import { CTokenCompoundingBase } from "contracts/market/collateral/CTokenCompoundingBase.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";

contract CTokenCompoundingBase_RescueTokenTest is TestBaseCTokenCompoundingBase {
    function setUp() public override {
        super.setUp();

        deal(address(cBALRETH), _ONE);
        deal(_USDC_ADDRESS, address(cBALRETH), 1e6);
    }

    function test_CTokenCompoundingBase_RescueToken_fail_whenCallerIsNotAuthorized() public {
        vm.prank(address(1));

        vm.expectRevert(CTokenCompoundingBase.CTokenCompoundingBase__Unauthorized.selector);
        cBALRETH.rescueToken(_USDC_ADDRESS, 100);
    }

    function test_CTokenCompoundingBase_RescueToken_fail_whenETHAmountExceedsBalance() public {
        uint256 balance = address(cBALRETH).balance;

        vm.expectRevert(SafeTransferLib.ETHTransferFailed.selector);
        cBALRETH.rescueToken(address(0), balance + 1);
    }

    function test_CTokenCompoundingBase_RescueToken_fail_whenTokenIsVaultToken() public {
        vm.expectRevert(CTokenCompoundingBase.CTokenCompoundingBase__TransferError.selector);
        cBALRETH.rescueToken(address(vault), 100);
    }

    function test_CTokenCompoundingBase_RescueToken_fail_whenTokenAmountExceedsBalance()
        public
    {
        uint256 balance = usdc.balanceOf(address(cBALRETH));

        vm.expectRevert(SafeTransferLib.TransferFailed.selector);
        cBALRETH.rescueToken(_USDC_ADDRESS, balance + 1);
    }

    function test_CTokenCompoundingBase_RescueToken_success() public {
        address daoOperator = centralRegistry.daoAddress();

        uint256 ethBalance = address(cBALRETH).balance;
        uint256 usdcBalance = usdc.balanceOf(address(cBALRETH));
        uint256 daoOperatorEthBalance = daoOperator.balance;
        uint256 daoOperatorUsdcBalance = usdc.balanceOf(daoOperator);

        cBALRETH.rescueToken(address(0), 100);
        cBALRETH.rescueToken(_USDC_ADDRESS, 100);

        assertEq(address(cBALRETH).balance, ethBalance - 100);
        assertEq(usdc.balanceOf(address(cBALRETH)), usdcBalance - 100);
        assertEq(daoOperator.balance, daoOperatorEthBalance + 100);
        assertEq(usdc.balanceOf(daoOperator), daoOperatorUsdcBalance + 100);
    }

    receive() external payable {}
}
