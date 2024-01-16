// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { SafeTransferLib } from "contracts/libraries/external/SafeTransferLib.sol";
import { VeCVE } from "contracts/token/VeCVE.sol";
import { TestBaseVeCVE } from "../TestBaseVeCVE.sol";

contract rescueTokenTest is TestBaseVeCVE {
    function setUp() public override {
        super.setUp();

        deal(_USDC_ADDRESS, address(veCVE), 100e8);
    }

    function test_rescueToken_fail_whenCallerIsNotAuthorized() public {
        vm.prank(address(1));

        vm.expectRevert(VeCVE.VeCVE__Unauthorized.selector);
        veCVE.rescueToken(_USDC_ADDRESS, 100);
    }

    function test_rescueToken_fail_whenTokenIsCVE() public {
        vm.expectRevert(VeCVE.VeCVE__NonTransferrable.selector);
        veCVE.rescueToken(address(cve), 100);
    }

    function test_rescueToken_fail_whenETHAmountExceedsBalance() public {
        uint256 balance = address(veCVE).balance;

        vm.expectRevert(SafeTransferLib.ETHTransferFailed.selector);
        veCVE.rescueToken(address(0), balance + 1);
    }

    function test_rescueToken_fail_whenAmountExceedsBalance() public {
        uint256 balance = usdc.balanceOf(address(veCVE));

        vm.expectRevert(SafeTransferLib.TransferFailed.selector);
        veCVE.rescueToken(_USDC_ADDRESS, balance + 1);
    }

    function test_rescueToken_success_withWithdrawAll() public {
        uint256 balance = usdc.balanceOf(address(veCVE));
        uint256 holding = usdc.balanceOf(address(this));

        veCVE.rescueToken(_USDC_ADDRESS, 0);

        assertEq(usdc.balanceOf(address(veCVE)), 0);
        assertEq(usdc.balanceOf(address(this)), holding + balance);
    }

    function test_rescueToken_success_fuzzed(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 100e8);

        uint256 balance = usdc.balanceOf(address(veCVE));
        uint256 holding = usdc.balanceOf(address(this));

        veCVE.rescueToken(_USDC_ADDRESS, amount);

        assertEq(usdc.balanceOf(address(veCVE)), balance - amount);
        assertEq(usdc.balanceOf(address(this)), holding + amount);
    }
}
