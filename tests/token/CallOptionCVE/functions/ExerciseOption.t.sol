// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseCallOptionCVE } from "../TestBaseCallOptionCVE.sol";
import { CallOptionCVE } from "contracts/token/CallOptionCVE.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract ExerciseOptionTest is TestBaseCallOptionCVE {
    address internal _E_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 public callOptionCVEBalance;

    event CallOptionCVEExercised(address indexed exerciser, uint256 amount);

    function setUp() public override {
        super.setUp();

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

        callOptionCVEBalance = callOptionCVE.balanceOf(address(this));
    }

    function test_exerciseOption_fail_whenAmountIsZero() public {
        vm.expectRevert("CallOptionCVE: invalid amount");
        callOptionCVE.exerciseOption(0);
    }

    function test_exerciseOption_fail_whenOptionsAreNotExercisable() public {
        skip(4 weeks);

        vm.expectRevert("CallOptionCVE: Options not exercisable yet");
        callOptionCVE.exerciseOption(callOptionCVEBalance);
    }

    function test_exerciseOption_fail_whenCVEIsNotEnough() public {
        vm.expectRevert("CallOptionCVE: not enough CVE remaining");
        callOptionCVE.exerciseOption(callOptionCVEBalance);
    }

    function test_exerciseOption_fail_whenOptionIsNotEnough() public {
        deal(address(cve), address(callOptionCVE), callOptionCVEBalance + 1);

        vm.expectRevert("CallOptionCVE: not enough call options to exercise");
        callOptionCVE.exerciseOption(callOptionCVEBalance + 1);
    }

    function test_exerciseOption_fail_whenMsgValueIsInvalid() public {
        chainlinkAdaptor.addAsset(_E_ADDRESS, _CHAINLINK_ETH_USD, true);
        priceRouter.addAssetPriceFeed(_E_ADDRESS, address(chainlinkAdaptor));

        callOptionCVE = new CallOptionCVE(
            ICentralRegistry(address(centralRegistry)),
            _E_ADDRESS
        );

        skip(1000);

        (uint256 paymentTokenCurrentPrice, ) = priceRouter.getPrice(
            _E_ADDRESS,
            true,
            true
        );

        callOptionCVE.setOptionsTerms(
            block.timestamp,
            paymentTokenCurrentPrice * _ONE
        );

        callOptionCVEBalance = callOptionCVE.balanceOf(address(this));

        deal(address(cve), address(callOptionCVE), callOptionCVEBalance);

        vm.expectRevert("CallOptionCVE: invalid msg value");
        callOptionCVE.exerciseOption{ value: callOptionCVEBalance - 1 }(
            callOptionCVEBalance
        );
    }

    function test_exerciseOption_success_withETH() public {
        chainlinkAdaptor.addAsset(_E_ADDRESS, _CHAINLINK_ETH_USD, true);
        priceRouter.addAssetPriceFeed(_E_ADDRESS, address(chainlinkAdaptor));

        callOptionCVE = new CallOptionCVE(
            ICentralRegistry(address(centralRegistry)),
            _E_ADDRESS
        );

        skip(1000);

        (uint256 paymentTokenCurrentPrice, ) = priceRouter.getPrice(
            _E_ADDRESS,
            true,
            true
        );

        callOptionCVE.setOptionsTerms(
            block.timestamp,
            paymentTokenCurrentPrice * _ONE
        );

        callOptionCVEBalance = callOptionCVE.balanceOf(address(this));

        deal(address(cve), address(callOptionCVE), callOptionCVEBalance);

        uint256 ethBalance = address(this).balance;
        uint256 callOptionCVEETHBalance = address(callOptionCVE).balance;

        vm.expectEmit(true, true, true, true, address(callOptionCVE));
        emit CallOptionCVEExercised(address(this), callOptionCVEBalance);

        callOptionCVE.exerciseOption{ value: callOptionCVEBalance }(
            callOptionCVEBalance
        );

        assertEq(address(this).balance, ethBalance - callOptionCVEBalance);
        assertEq(
            address(callOptionCVE).balance,
            callOptionCVEETHBalance + callOptionCVEBalance
        );
    }

    function test_exerciseOption_success_withERC20() public {
        callOptionCVEBalance = callOptionCVE.balanceOf(address(this));

        deal(address(cve), address(callOptionCVE), callOptionCVEBalance);
        deal(_USDC_ADDRESS, address(this), callOptionCVEBalance);

        uint256 usdcBalance = usdc.balanceOf(address(this));
        uint256 callOptionCVEUSDCBalance = usdc.balanceOf(
            address(callOptionCVE)
        );

        usdc.approve(address(callOptionCVE), callOptionCVEBalance);

        vm.expectEmit(true, true, true, true, address(callOptionCVE));
        emit CallOptionCVEExercised(address(this), callOptionCVEBalance);

        callOptionCVE.exerciseOption(callOptionCVEBalance);

        assertEq(
            usdc.balanceOf(address(this)),
            usdcBalance - callOptionCVEBalance
        );
        assertEq(
            usdc.balanceOf(address(callOptionCVE)),
            callOptionCVEUSDCBalance + callOptionCVEBalance
        );
    }
}
