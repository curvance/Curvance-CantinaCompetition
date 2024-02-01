// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseOCVE } from "../TestBaseOCVE.sol";

import { OCVE } from "contracts/token/OCVE.sol";
import { FixedPointMathLib } from "contracts/libraries/FixedPointMathLib.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract ExerciseOptionTest is TestBaseOCVE {
    address internal _E_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 public oCVEBalance;

    event OptionsExercised(address indexed exerciser, uint256 amount);

    function setUp() public override {
        super.setUp();

        skip(1000);

        (uint256 paymentTokenCurrentPrice, ) = oracleRouter.getPrice(
            _USDC_ADDRESS,
            true,
            true
        );

        oCVE.setOptionsTerms(block.timestamp, paymentTokenCurrentPrice * _ONE);

        oCVEBalance = oCVE.balanceOf(address(this));
    }

    function test_exerciseOption_fail_whenAmountIsZero() public {
        vm.expectRevert(OCVE.OCVE__ParametersAreInvalid.selector);
        oCVE.exerciseOption(0);
    }

    function test_exerciseOption_fail_whenOptionsAreNotExercisable() public {
        skip(4 weeks);

        vm.expectRevert(OCVE.OCVE__CannotExercise.selector);
        oCVE.exerciseOption(oCVEBalance);
    }

    function test_exerciseOption_fail_whenCVEIsNotEnough() public {
        vm.expectRevert(OCVE.OCVE__CannotExercise.selector);
        oCVE.exerciseOption(oCVEBalance);
    }

    function test_exerciseOption_fail_whenOptionIsNotEnough() public {
        deal(address(cve), address(oCVE), oCVEBalance + 1);

        vm.expectRevert(OCVE.OCVE__CannotExercise.selector);
        oCVE.exerciseOption(oCVEBalance + 1);
    }

    function test_exerciseOption_fail_whenMsgValueIsInvalid() public {
        chainlinkAdaptor.addAsset(_E_ADDRESS, _CHAINLINK_ETH_USD, 0, true);
        oracleRouter.addAssetPriceFeed(_E_ADDRESS, address(chainlinkAdaptor));

        oCVE = new OCVE(
            ICentralRegistry(address(centralRegistry)),
            _E_ADDRESS
        );

        skip(1000);

        (uint256 paymentTokenCurrentPrice, ) = oracleRouter.getPrice(
            _E_ADDRESS,
            true,
            true
        );

        oCVE.setOptionsTerms(block.timestamp, paymentTokenCurrentPrice * _ONE);

        oCVEBalance = oCVE.balanceOf(address(this));

        deal(address(cve), address(oCVE), oCVEBalance);

        vm.expectRevert(OCVE.OCVE__CannotExercise.selector);
        oCVE.exerciseOption{ value: oCVEBalance - 1 }(oCVEBalance);
    }

    function test_exerciseOption_success_withETH_fuzzed(
        uint256 amount
    ) public {
        vm.assume(amount >= 1e18 && amount < 1_000_000_000e18);

        chainlinkAdaptor.addAsset(_E_ADDRESS, _CHAINLINK_ETH_USD, 0, true);
        oracleRouter.addAssetPriceFeed(_E_ADDRESS, address(chainlinkAdaptor));

        oCVE = new OCVE(
            ICentralRegistry(address(centralRegistry)),
            _E_ADDRESS
        );

        skip(1000);

        (uint256 paymentTokenCurrentPrice, ) = oracleRouter.getPrice(
            _E_ADDRESS,
            true,
            true
        );

        oCVE.setOptionsTerms(block.timestamp, paymentTokenCurrentPrice * _ONE);

        deal(address(this), amount);
        deal(address(oCVE), address(this), amount);
        deal(address(cve), address(oCVE), amount);

        uint256 ethBalance = address(this).balance;
        uint256 oCVEETHBalance = address(oCVE).balance;

        vm.expectEmit(true, true, true, true, address(oCVE));
        emit OptionsExercised(address(this), amount);

        oCVE.exerciseOption{ value: amount }(amount);

        assertEq(address(this).balance, ethBalance - amount);
        assertEq(address(oCVE).balance, oCVEETHBalance + amount);
    }

    function test_exerciseOption_success_withERC20_fuzzed(
        uint256 amount
    ) public {
        vm.assume(amount >= 1e18 && amount < 1_000_000_000e18);

        uint256 oCVEUSDCBalance = usdc.balanceOf(address(oCVE));
        uint256 optionExerciseCost = (amount * oCVE.paymentTokenPerCVE()) /
            1e18;
        uint256 payAmount = FixedPointMathLib.mulDivUp(
            optionExerciseCost,
            amount * 1e12,
            1e18
        );

        deal(address(oCVE), address(this), amount);
        deal(address(cve), address(oCVE), amount);
        deal(_USDC_ADDRESS, address(this), payAmount * 3);

        usdc.approve(address(oCVE), payAmount);

        // We have extra checks here because its possible payAmount
        // becomes 0 due to rounding with USDC decimals != 18.
        if (payAmount == 0) {
            vm.expectRevert(OCVE.OCVE__CannotExercise.selector);

            oCVE.exerciseOption(amount);
        } else {
            vm.expectEmit(true, true, true, true, address(oCVE));
            emit OptionsExercised(address(this), amount);

            oCVE.exerciseOption(amount);

            assertEq(usdc.balanceOf(address(this)), payAmount * 2);
            assertEq(
                usdc.balanceOf(address(oCVE)),
                oCVEUSDCBalance + payAmount
            );
        }
    }
}
