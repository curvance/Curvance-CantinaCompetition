// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseOCVE } from "../TestBaseOCVE.sol";

contract OCVERescueTokenTest is TestBaseOCVE {
    function setUp() public override {
        super.setUp();

        deal(address(oCVE), _ONE);
        deal(_USDC_ADDRESS, address(oCVE), 1e6);
    }

    function test_oCVERescueToken_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.prank(address(1));

        vm.expectRevert("OCVE: UNAUTHORIZED");
        oCVE.rescueToken(_USDC_ADDRESS, user1, 100);
    }

    function test_oCVERescueToken_fail_whenRecipientIsZeroAddress()
        public
    {
        vm.expectRevert(OCVE.OCVE__ParametersareInvalid.selector);
        oCVE.rescueToken(_USDC_ADDRESS, address(0), 100);
    }

    function test_oCVERescueToken_fail_whenETHAmountExceedsBalance()
        public
    {
        uint256 balance = address(oCVE).balance;

        vm.expectRevert(OCVE.OCVE__ParametersareInvalid.selector);
        oCVE.rescueToken(address(0), user1, balance + 1);
    }

    function test_oCVERescueToken_fail_whenTokenIsTransferCVE()
        public
    {
        vm.expectRevert(OCVE.OCVE__TransferError.selector);
        oCVE.rescueToken(address(cve), user1, 100);
    }

    function test_oCVERescueToken_fail_whenTokenAmountExceedsBalance()
        public
    {
        uint256 balance = usdc.balanceOf(address(oCVE));

        vm.expectRevert(OCVE.OCVE__ParametersareInvalid.selector);
        oCVE.rescueToken(_USDC_ADDRESS, user1, balance + 1);
    }

    function test_oCVERescueToken_success() public {
        uint256 ethBalance = address(oCVE).balance;
        uint256 usdcBalance = usdc.balanceOf(address(oCVE));
        uint256 userEthBalance = user1.balance;
        uint256 userUsdcBalance = usdc.balanceOf(user1);

        oCVE.rescueToken(address(0), user1, 100);
        oCVE.rescueToken(_USDC_ADDRESS, user1, 100);

        assertEq(address(oCVE).balance, ethBalance - 100);
        assertEq(usdc.balanceOf(address(oCVE)), usdcBalance - 100);
        assertEq(user1.balance, userEthBalance + 100);
        assertEq(usdc.balanceOf(user1), userUsdcBalance + 100);
    }

    receive() external payable {}
}
