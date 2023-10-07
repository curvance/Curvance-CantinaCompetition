// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseCVELocker } from "../TestBaseCVELocker.sol";
import { CVELocker } from "contracts/architecture/CVELocker.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";

contract CVELockerRecoverTokenTest is TestBaseCVELocker {
    event TokenRecovered(address token, address to, uint256 amount);

    function setUp() public override {
        super.setUp();

        deal(_DAI_ADDRESS, address(cveLocker), 100e8);
    }

    function test_cveLockerRecoverToken_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.prank(address(1));

        vm.expectRevert(CVELocker.CVELocker__Unauthorized.selector);
        cveLocker.recoverToken(_DAI_ADDRESS, address(this), 100);
    }

    function test_cveLockerRecoverToken_fail_whenTokenIsBaseRewardToken()
        public
    {
        vm.expectRevert(CVELocker.CVELocker__Unauthorized.selector);
        cveLocker.recoverToken(_USDC_ADDRESS, address(this), 100);
    }

    function test_cveLockerRecoverToken_fail_whenAmountExceedsBalance()
        public
    {
        uint256 balance = dai.balanceOf(address(cveLocker));

        vm.expectRevert(SafeTransferLib.TransferFailed.selector);
        cveLocker.recoverToken(_DAI_ADDRESS, address(this), balance + 1);
    }

    function test_cveLockerRecoverToken_success_withWithdrawAll() public {
        uint256 balance = dai.balanceOf(address(cveLocker));
        uint256 holding = dai.balanceOf(address(this));

        cveLocker.recoverToken(_DAI_ADDRESS, address(this), 0);

        assertEq(dai.balanceOf(address(cveLocker)), 0);
        assertEq(dai.balanceOf(address(this)), holding + balance);
    }

    function test_cveLockerRecoverToken_success_fuzzed(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 100e8);

        uint256 balance = dai.balanceOf(address(cveLocker));
        uint256 holding = dai.balanceOf(address(this));

        vm.expectEmit(true, true, true, true, address(cveLocker));
        emit TokenRecovered(_DAI_ADDRESS, address(this), amount);

        cveLocker.recoverToken(_DAI_ADDRESS, address(this), amount);

        assertEq(dai.balanceOf(address(cveLocker)), balance - amount);
        assertEq(dai.balanceOf(address(this)), holding + amount);
    }
}
