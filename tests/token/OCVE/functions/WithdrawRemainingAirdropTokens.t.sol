// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseOCVE } from "../TestBaseOCVE.sol";
import { OCVE } from "contracts/token/OCVE.sol";

contract WithdrawRemainingAirdropTokensTest is TestBaseOCVE {
    event RemainingCVEWithdrawn(uint256 amount);

    function test_withdrawRemainingAirdropTokens_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.prank(address(1));

        vm.expectRevert("OCVE: UNAUTHORIZED");
        oCVE.withdrawRemainingAirdropTokens();
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

        oCVE.setOptionsTerms(
            block.timestamp,
            paymentTokenCurrentPrice * _ONE
        );

        skip(3 weeks);

        vm.expectRevert(OCVE.OCVE__TransferError.selector);
        oCVE.withdrawRemainingAirdropTokens();
    }

    function test_withdrawRemainingAirdropTokens_success() public {
        skip(1000);

        (uint256 paymentTokenCurrentPrice, ) = priceRouter.getPrice(
            _USDC_ADDRESS,
            true,
            true
        );

        oCVE.setOptionsTerms(
            block.timestamp,
            paymentTokenCurrentPrice * _ONE
        );

        skip(4 weeks + 1);

        deal(address(cve), address(oCVE), _ONE);
        uint256 cveBalance = cve.balanceOf(address(this));

        assertEq(cve.balanceOf(address(oCVE)), _ONE);

        vm.expectEmit(true, true, true, true, address(oCVE));
        emit RemainingCVEWithdrawn(_ONE);

        oCVE.withdrawRemainingAirdropTokens();

        assertEq(cve.balanceOf(address(oCVE)), 0);
        assertEq(cve.balanceOf(address(this)), cveBalance + _ONE);
    }
}
