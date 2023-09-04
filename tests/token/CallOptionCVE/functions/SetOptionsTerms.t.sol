// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseCallOptionCVE } from "../TestBaseCallOptionCVE.sol";

contract SetOptionsTermsTest is TestBaseCallOptionCVE {
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

        vm.expectRevert("CallOptionCVE: UNAUTHORIZED");
        callOptionCVE.setOptionsTerms(
            block.timestamp,
            paymentTokenCurrentPrice * _ONE
        );
    }

    function test_setOptionsTerms_fail_whenStrikePriceIsZero() public {
        vm.expectRevert("CallOptionCVE: Strike price is invalid");
        callOptionCVE.setOptionsTerms(block.timestamp, 0);
    }

    function test_setOptionsTerms_fail_whenStartTimestampIsInvalid() public {
        vm.expectRevert("CallOptionCVE: Start timestamp is invalid");
        callOptionCVE.setOptionsTerms(
            block.timestamp - 1,
            paymentTokenCurrentPrice * _ONE
        );
    }

    function test_setOptionsTerms_fail_whenOptionsExercisingIsAlreadyActive()
        public
    {
        callOptionCVE.setOptionsTerms(
            block.timestamp,
            paymentTokenCurrentPrice * _ONE
        );

        vm.expectRevert("CallOptionCVE: Options exercising already active");
        callOptionCVE.setOptionsTerms(
            block.timestamp,
            paymentTokenCurrentPrice * _ONE
        );
    }

    function test_setOptionsTerms_fail_whenStrikePriceIsInvalid() public {
        vm.expectRevert("CallOptionCVE: invalid strike price configuration");
        callOptionCVE.setOptionsTerms(
            block.timestamp,
            paymentTokenCurrentPrice
        );
    }

    function test_setOptionsTerms_success() public {
        callOptionCVE.setOptionsTerms(
            block.timestamp,
            paymentTokenCurrentPrice * _ONE * 2
        );

        assertEq(callOptionCVE.optionsStartTimestamp(), block.timestamp);
        assertEq(
            callOptionCVE.optionsEndTimestamp(),
            block.timestamp + 4 weeks
        );
        assertEq(callOptionCVE.paymentTokenPerCVE(), 2);
    }
}
