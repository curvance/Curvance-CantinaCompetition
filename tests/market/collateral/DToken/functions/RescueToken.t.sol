// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseDToken } from "../TestBaseDToken.sol";
import { DToken } from "contracts/market/collateral/DToken.sol";
import { SafeTransferLib } from "contracts/libraries/external/SafeTransferLib.sol";

contract DTokenRescueTokenTest is TestBaseDToken {
    function setUp() public override {
        super.setUp();

        deal(address(dUSDC), _ONE);
        deal(_DAI_ADDRESS, address(dUSDC), _ONE);
    }

    function test_dTokenRescueToken_fail_whenCallerIsNotAuthorized() public {
        vm.prank(address(1));

        vm.expectRevert(DToken.DToken__Unauthorized.selector);
        dUSDC.rescueToken(_USDC_ADDRESS, 100);
    }

    function test_dTokenRescueToken_fail_whenETHAmountExceedsBalance() public {
        uint256 balance = address(dUSDC).balance;

        vm.expectRevert(SafeTransferLib.ETHTransferFailed.selector);
        dUSDC.rescueToken(address(0), balance + 1);
    }

    function test_dTokenRescueToken_fail_whenTokenIsUnderlyingToken() public {
        vm.expectRevert(DToken.DToken__TransferError.selector);
        dUSDC.rescueToken(_USDC_ADDRESS, 100);
    }

    function test_dTokenRescueToken_fail_whenTokenAmountExceedsBalance()
        public
    {
        uint256 balance = dai.balanceOf(address(dUSDC));

        vm.expectRevert(SafeTransferLib.TransferFailed.selector);
        dUSDC.rescueToken(_DAI_ADDRESS, balance + 1);
    }

    function test_dTokenRescueToken_success() public {
        address daoOperator = centralRegistry.daoAddress();

        uint256 ethBalance = address(dUSDC).balance;
        uint256 daiBalance = dai.balanceOf(address(dUSDC));
        uint256 daoOperatorEthBalance = daoOperator.balance;
        uint256 daoOperatorDaiBalance = dai.balanceOf(daoOperator);

        dUSDC.rescueToken(address(0), 100);
        dUSDC.rescueToken(_DAI_ADDRESS, 100);

        assertEq(address(dUSDC).balance, ethBalance - 100);
        assertEq(dai.balanceOf(address(dUSDC)), daiBalance - 100);
        assertEq(daoOperator.balance, daoOperatorEthBalance + 100);
        assertEq(dai.balanceOf(daoOperator), daoOperatorDaiBalance + 100);
    }

    receive() external payable {}
}
