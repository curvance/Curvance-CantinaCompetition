// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseCallOptionCVE } from "../TestBaseCallOptionCVE.sol";

contract WithdrawRemainingAirdropTokensTest is TestBaseCallOptionCVE {
    event RemainingCVEWithdrawn(uint256 amount);

    function test_withdrawRemainingAirdropTokens_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.prank(address(1));

        vm.expectRevert("CallOptionCVE: UNAUTHORIZED");
        callOptionCVE.withdrawRemainingAirdropTokens();
    }

    function test_withdrawRemainingAirdropTokens_fail_whenWithdrawTooEarly()
        public
    {
        skip(1000);

        (uint256 paymentTokenCurrentPrice, ) = priceRouter.getPrice(
            _USDC_ADDRESS,
            true,
            true
        );

        callOptionCVE.setOptionsTerms(
            block.timestamp,
            paymentTokenCurrentPrice * _ONE
        );

        skip(4 weeks);

        vm.expectRevert("CallOptionCVE: Too early");
        callOptionCVE.withdrawRemainingAirdropTokens();
    }

    function test_withdrawRemainingAirdropTokens_success() public {
        skip(1000);

        (uint256 paymentTokenCurrentPrice, ) = priceRouter.getPrice(
            _USDC_ADDRESS,
            true,
            true
        );

        callOptionCVE.setOptionsTerms(
            block.timestamp,
            paymentTokenCurrentPrice * _ONE
        );

        skip(4 weeks + 1);

        deal(address(cve), address(callOptionCVE), _ONE);
        uint256 cveBalance = cve.balanceOf(address(this));

        assertEq(cve.balanceOf(address(callOptionCVE)), _ONE);

        vm.expectEmit(true, true, true, true, address(callOptionCVE));
        emit RemainingCVEWithdrawn(_ONE);

        callOptionCVE.withdrawRemainingAirdropTokens();

        assertEq(cve.balanceOf(address(callOptionCVE)), 0);
        assertEq(cve.balanceOf(address(this)), cveBalance + _ONE);
    }
}
