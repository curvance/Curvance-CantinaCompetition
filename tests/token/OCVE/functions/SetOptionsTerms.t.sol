// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseOCVE } from "../TestBaseOCVE.sol";
import { OCVE } from "contracts/token/OCVE.sol";

contract SetOptionsTermsTest is TestBaseOCVE {
    uint256 public paymentTokenCurrentPrice;

    function setUp() public override {
        super.setUp();

        skip(1000);

        (paymentTokenCurrentPrice, ) = priceRouter.getPrice(
            _USDC_ADDRESS,
            true,
            true
        );
    }

    function test_setOptionsTerms_fail_whenCallerIsNotAuthorized() public {
        vm.prank(address(1));

        vm.expectRevert(OCVE.OCVE__Unauthorized.selector);
        oCVE.setOptionsTerms(block.timestamp, paymentTokenCurrentPrice * _ONE);
    }

    function test_setOptionsTerms_fail_whenStrikePriceIsZero() public {
        vm.expectRevert(OCVE.OCVE__ParametersareInvalid.selector);
        oCVE.setOptionsTerms(block.timestamp, 0);
    }

    function test_setOptionsTerms_fail_whenStartTimestampIsInvalid() public {
        vm.expectRevert(OCVE.OCVE__ParametersareInvalid.selector);
        oCVE.setOptionsTerms(
            block.timestamp - 1,
            paymentTokenCurrentPrice * _ONE
        );
    }

    function test_setOptionsTerms_fail_whenOptionsExercisingIsAlreadyActive()
        public
    {
        oCVE.setOptionsTerms(block.timestamp, paymentTokenCurrentPrice * _ONE);
        skip(1 weeks);

        vm.expectRevert(OCVE.OCVE__ConfigurationError.selector);
        oCVE.setOptionsTerms(block.timestamp, paymentTokenCurrentPrice * _ONE);
    }

    function test_setOptionsTerms_fail_whenStrikePriceIsInvalid() public {
        vm.expectRevert(OCVE.OCVE__ParametersareInvalid.selector);
        oCVE.setOptionsTerms(block.timestamp, paymentTokenCurrentPrice);
    }

    function test_setOptionsTerms_success() public {
        oCVE.setOptionsTerms(
            block.timestamp,
            paymentTokenCurrentPrice * _ONE * 2
        );

        assertEq(oCVE.optionsStartTimestamp(), block.timestamp);
        assertEq(oCVE.optionsEndTimestamp(), block.timestamp + 4 weeks);
        assertEq(oCVE.paymentTokenPerCVE(), 2e18);
    }
}
