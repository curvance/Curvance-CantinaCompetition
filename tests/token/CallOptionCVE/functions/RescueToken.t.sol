// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseCallOptionCVE } from "../TestBaseCallOptionCVE.sol";

contract CallOptionCVERescueTokenTest is TestBaseCallOptionCVE {
    function setUp() public override {
        super.setUp();

        deal(address(callOptionCVE), _ONE);
        deal(_USDC_ADDRESS, address(callOptionCVE), 1e6);
    }

    function test_callOptionCVERescueToken_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.prank(address(1));

        vm.expectRevert("CallOptionCVE: UNAUTHORIZED");
        callOptionCVE.rescueToken(_USDC_ADDRESS, user1, 100);
    }

    function test_callOptionCVERescueToken_fail_whenRecipientIsZeroAddress()
        public
    {
        vm.expectRevert("CallOptionCVE: invalid recipient address");
        callOptionCVE.rescueToken(_USDC_ADDRESS, address(0), 100);
    }

    function test_callOptionCVERescueToken_fail_whenETHAmountExceedsBalance()
        public
    {
        uint256 balance = address(callOptionCVE).balance;

        vm.expectRevert("CallOptionCVE: insufficient balance");
        callOptionCVE.rescueToken(address(0), user1, balance + 1);
    }

    function test_callOptionCVERescueToken_fail_whenTokenIsTransferCVE()
        public
    {
        vm.expectRevert("CallOptionCVE: cannot withdraw CVE");
        callOptionCVE.rescueToken(address(cve), user1, 100);
    }

    function test_callOptionCVERescueToken_fail_whenTokenAmountExceedsBalance()
        public
    {
        uint256 balance = usdc.balanceOf(address(callOptionCVE));

        vm.expectRevert("CallOptionCVE: insufficient balance");
        callOptionCVE.rescueToken(_USDC_ADDRESS, user1, balance + 1);
    }

    function test_callOptionCVERescueToken_success() public {
        uint256 ethBalance = address(callOptionCVE).balance;
        uint256 usdcBalance = usdc.balanceOf(address(callOptionCVE));
        uint256 userEthBalance = user1.balance;
        uint256 userUsdcBalance = usdc.balanceOf(user1);

        callOptionCVE.rescueToken(address(0), user1, 100);
        callOptionCVE.rescueToken(_USDC_ADDRESS, user1, 100);

        assertEq(address(callOptionCVE).balance, ethBalance - 100);
        assertEq(usdc.balanceOf(address(callOptionCVE)), usdcBalance - 100);
        assertEq(user1.balance, userEthBalance + 100);
        assertEq(usdc.balanceOf(user1), userUsdcBalance + 100);
    }

    receive() external payable {}
}
