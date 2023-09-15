// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseOCVE } from "../TestBaseOCVE.sol";

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

        vm.expectRevert("OCVE: UNAUTHORIZED");
        oCVE.setOptionsTerms(
            block.timestamp,
            paymentTokenCurrentPrice * _ONE
        );
    }

    function test_setOptionsTerms_fail_whenStrikePriceIsZero() public {
        vm.expectRevert("OCVE: Strike price is invalid");
        oCVE.setOptionsTerms(block.timestamp, 0);
    }

    function test_setOptionsTerms_fail_whenStartTimestampIsInvalid() public {
        vm.expectRevert("OCVE: Start timestamp is invalid");
        oCVE.setOptionsTerms(
            block.timestamp - 1,
            paymentTokenCurrentPrice * _ONE
        );
    }

    function test_setOptionsTerms_fail_whenOptionsExercisingIsAlreadyActive()
        public
    {
        oCVE.setOptionsTerms(
            block.timestamp,
            paymentTokenCurrentPrice * _ONE
        );

        vm.expectRevert("OCVE: Options exercising already active");
        oCVE.setOptionsTerms(
            block.timestamp,
            paymentTokenCurrentPrice * _ONE
        );
    }

    function test_setOptionsTerms_fail_whenStrikePriceIsInvalid() public {
        vm.expectRevert("OCVE: invalid strike price configuration");
        oCVE.setOptionsTerms(
            block.timestamp,
            paymentTokenCurrentPrice
        );
    }

    function test_setOptionsTerms_success() public {
        oCVE.setOptionsTerms(
            block.timestamp,
            paymentTokenCurrentPrice * _ONE * 2
        );

        assertEq(oCVE.optionsStartTimestamp(), block.timestamp);
        assertEq(
            oCVE.optionsEndTimestamp(),
            block.timestamp + 4 weeks
        );
        assertEq(oCVE.paymentTokenPerCVE(), 2);
    }
}
