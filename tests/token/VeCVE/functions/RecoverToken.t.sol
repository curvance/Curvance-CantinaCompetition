// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";
import { VeCVE } from "contracts/token/VeCVE.sol";
import { TestBaseVeCVE } from "../TestBaseVeCVE.sol";

contract RecoverTokenTest is TestBaseVeCVE {
    event TokenRecovered(address token, address to, uint256 amount);

    function setUp() public override {
        super.setUp();

        deal(_USDC_ADDRESS, address(veCVE), 100e8);
    }

    function test_recoverToken_fail_whenCallerIsNotAuthorized() public {
        vm.prank(address(1));

        vm.expectRevert("VeCVE: UNAUTHORIZED");
        veCVE.recoverToken(_USDC_ADDRESS, address(this), 100);
    }

    function test_recoverToken_fail_whenTokenIsCVE() public {
        vm.expectRevert("cannot withdraw cve token");
        veCVE.recoverToken(address(cve), address(this), 100);
    }

    function test_recoverToken_fail_whenAmountExceedsBalance() public {
        uint256 balance = usdc.balanceOf(address(veCVE));

        vm.expectRevert(SafeTransferLib.TransferFailed.selector);
        veCVE.recoverToken(_USDC_ADDRESS, address(this), balance + 1);
    }

    function test_recoverToken_success_withWithdrawAll() public {
        uint256 balance = usdc.balanceOf(address(veCVE));
        uint256 holding = usdc.balanceOf(address(this));

        vm.expectEmit(true, true, true, true, address(veCVE));
        emit TokenRecovered(_USDC_ADDRESS, address(this), balance);

        veCVE.recoverToken(_USDC_ADDRESS, address(this), 0);

        assertEq(usdc.balanceOf(address(veCVE)), 0);
        assertEq(usdc.balanceOf(address(this)), holding + balance);
    }

    function test_recoverToken_success_fuzzed(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 100e8);

        uint256 balance = usdc.balanceOf(address(veCVE));
        uint256 holding = usdc.balanceOf(address(this));

        vm.expectEmit(true, true, true, true, address(veCVE));
        emit TokenRecovered(_USDC_ADDRESS, address(this), amount);

        veCVE.recoverToken(_USDC_ADDRESS, address(this), amount);

        assertEq(usdc.balanceOf(address(veCVE)), balance - amount);
        assertEq(usdc.balanceOf(address(this)), holding + amount);
    }
}
