// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseOCVE } from "../TestBaseOCVE.sol";
import { OCVE } from "contracts/token/OCVE.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";

contract OCVERescueTokenTest is TestBaseOCVE {
    function setUp() public override {
        super.setUp();

        deal(address(oCVE), _ONE);
        deal(_USDC_ADDRESS, address(oCVE), 1e6);
    }

    function test_oCVERescueToken_fail_whenCallerIsNotAuthorized() public {
        vm.prank(address(1));

        vm.expectRevert(OCVE.OCVE__Unauthorized.selector);
        oCVE.rescueToken(_USDC_ADDRESS, 100);
    }

    function test_oCVERescueToken_fail_whenETHAmountExceedsBalance() public {
        uint256 balance = address(oCVE).balance;

        vm.expectRevert(SafeTransferLib.ETHTransferFailed.selector);
        oCVE.rescueToken(address(0), balance + 1);
    }

    function test_oCVERescueToken_fail_whenTokenIsTransferCVE() public {
        vm.expectRevert(OCVE.OCVE__TransferError.selector);
        oCVE.rescueToken(address(cve), 100);
    }

    function test_oCVERescueToken_fail_whenTokenAmountExceedsBalance() public {
        uint256 balance = usdc.balanceOf(address(oCVE));

        vm.expectRevert(SafeTransferLib.TransferFailed.selector);
        oCVE.rescueToken(_USDC_ADDRESS, balance + 1);
    }

    function test_oCVERescueToken_success() public {
        uint256 ethBalance = address(oCVE).balance;
        uint256 usdcBalance = usdc.balanceOf(address(oCVE));

        address dao = address(centralRegistry.daoAddress());
        uint256 userEthBalance = dao.balance;
        uint256 userUsdcBalance = usdc.balanceOf(dao);

        oCVE.rescueToken(address(0), 100);
        oCVE.rescueToken(_USDC_ADDRESS, 100);

        assertEq(address(oCVE).balance, ethBalance - 100);
        assertEq(usdc.balanceOf(address(oCVE)), usdcBalance - 100);

        assertEq(dao.balance, userEthBalance + 100);
        assertEq(usdc.balanceOf(dao), userUsdcBalance + 100);
    }

    receive() external payable {}
}
