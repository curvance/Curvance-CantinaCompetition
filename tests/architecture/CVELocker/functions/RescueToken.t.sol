// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseCVELocker } from "../TestBaseCVELocker.sol";
import { CVELocker } from "contracts/architecture/CVELocker.sol";
import { SafeTransferLib } from "contracts/libraries/external/SafeTransferLib.sol";

contract CVELockerRescueTokenTest is TestBaseCVELocker {
    function setUp() public override {
        super.setUp();

        deal(_DAI_ADDRESS, address(cveLocker), 100e18);
        deal(address(cveLocker), 100e18);
    }

    function test_cveLockerRescueToken_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.prank(address(1));

        vm.expectRevert(CVELocker.CVELocker__Unauthorized.selector);
        cveLocker.rescueToken(_DAI_ADDRESS, 100);
    }

    function test_cveLockerRescueToken_fail_whenTokenIsRewardToken() public {
        vm.expectRevert(CVELocker.CVELocker__Unauthorized.selector);
        cveLocker.rescueToken(_USDC_ADDRESS, 100);
    }

    function test_cveLockerRescueToken_fail_whenAmountExceedsBalance() public {
        uint256 balance = dai.balanceOf(address(cveLocker));

        vm.expectRevert(SafeTransferLib.TransferFailed.selector);
        cveLocker.rescueToken(_DAI_ADDRESS, balance + 1);
    }

    function test_cveLockerRescueToken_success_withNativeAsset_withWithdrawAll()
        public
    {
        uint256 balance = address(cveLocker).balance;
        uint256 holding = address(this).balance;

        cveLocker.rescueToken(address(0), 0);

        assertEq(address(cveLocker).balance, 0);
        assertEq(address(this).balance, holding + balance);
    }

    function test_cveLockerRescueToken_success_withNativeAsset_fuzzed(
        uint256 amount
    ) public {
        vm.assume(amount > 0 && amount <= 100e18);

        uint256 balance = address(cveLocker).balance;
        uint256 holding = address(this).balance;

        cveLocker.rescueToken(address(0), amount);

        assertEq(address(cveLocker).balance, balance - amount);
        assertEq(address(this).balance, holding + amount);
    }

    function test_cveLockerRescueToken_success_withNonNativeAsset_withWithdrawAll()
        public
    {
        uint256 balance = dai.balanceOf(address(cveLocker));
        uint256 holding = dai.balanceOf(address(this));

        cveLocker.rescueToken(_DAI_ADDRESS, 0);

        assertEq(dai.balanceOf(address(cveLocker)), 0);
        assertEq(dai.balanceOf(address(this)), holding + balance);
    }

    function test_cveLockerRescueToken_success_withNonNativeAsset_fuzzed(
        uint256 amount
    ) public {
        vm.assume(amount > 0 && amount <= 100e18);

        uint256 balance = dai.balanceOf(address(cveLocker));
        uint256 holding = dai.balanceOf(address(this));

        cveLocker.rescueToken(_DAI_ADDRESS, amount);

        assertEq(dai.balanceOf(address(cveLocker)), balance - amount);
        assertEq(dai.balanceOf(address(this)), holding + amount);
    }
}
