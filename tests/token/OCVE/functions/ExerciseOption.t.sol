// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseOCVE } from "../TestBaseOCVE.sol";
import { OCVE } from "contracts/token/OCVE.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract ExerciseOptionTest is TestBaseOCVE {
    address internal _E_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 public oCVEBalance;

    event OptionsExercised(address indexed exerciser, uint256 amount);

    function setUp() public override {
        super.setUp();

        skip(1000);

        (uint256 paymentTokenCurrentPrice, ) = priceRouter.getPrice(
            _USDC_ADDRESS,
            true,
            true
        );

        oCVE.setOptionsTerms(block.timestamp, paymentTokenCurrentPrice * _ONE);

        oCVEBalance = oCVE.balanceOf(address(this));
    }

    function test_exerciseOption_fail_whenAmountIsZero() public {
        vm.expectRevert("OCVE: invalid amount");
        oCVE.exerciseOption(0);
    }

    function test_exerciseOption_fail_whenOptionsAreNotExercisable() public {
        skip(4 weeks);

        vm.expectRevert("OCVE: Options not exercisable yet");
        oCVE.exerciseOption(oCVEBalance);
    }

    function test_exerciseOption_fail_whenCVEIsNotEnough() public {
        vm.expectRevert("OCVE: not enough CVE remaining");
        oCVE.exerciseOption(oCVEBalance);
    }

    function test_exerciseOption_fail_whenOptionIsNotEnough() public {
        deal(address(cve), address(oCVE), oCVEBalance + 1);

        vm.expectRevert("OCVE: not enough call options to exercise");
        oCVE.exerciseOption(oCVEBalance + 1);
    }

    function test_exerciseOption_fail_whenMsgValueIsInvalid() public {
        chainlinkAdaptor.addAsset(_E_ADDRESS, _CHAINLINK_ETH_USD, true);
        priceRouter.addAssetPriceFeed(_E_ADDRESS, address(chainlinkAdaptor));

        oCVE = new OCVE(
            ICentralRegistry(address(centralRegistry)),
            _E_ADDRESS
        );

        skip(1000);

        (uint256 paymentTokenCurrentPrice, ) = priceRouter.getPrice(
            _E_ADDRESS,
            true,
            true
        );

        oCVE.setOptionsTerms(block.timestamp, paymentTokenCurrentPrice * _ONE);

        oCVEBalance = oCVE.balanceOf(address(this));

        deal(address(cve), address(oCVE), oCVEBalance);

        vm.expectRevert("OCVE: invalid msg value");
        oCVE.exerciseOption{ value: oCVEBalance - 1 }(oCVEBalance);
    }

    function test_exerciseOption_success_withETH() public {
        chainlinkAdaptor.addAsset(_E_ADDRESS, _CHAINLINK_ETH_USD, true);
        priceRouter.addAssetPriceFeed(_E_ADDRESS, address(chainlinkAdaptor));

        oCVE = new OCVE(
            ICentralRegistry(address(centralRegistry)),
            _E_ADDRESS
        );

        skip(1000);

        (uint256 paymentTokenCurrentPrice, ) = priceRouter.getPrice(
            _E_ADDRESS,
            true,
            true
        );

        oCVE.setOptionsTerms(block.timestamp, paymentTokenCurrentPrice * _ONE);

        oCVEBalance = oCVE.balanceOf(address(this));

        deal(address(cve), address(oCVE), oCVEBalance);

        uint256 ethBalance = address(this).balance;
        uint256 oCVEETHBalance = address(oCVE).balance;

        vm.expectEmit(true, true, true, true, address(oCVE));
        emit OptionsExercised(address(this), oCVEBalance);

        oCVE.exerciseOption{ value: oCVEBalance }(oCVEBalance);

        assertEq(address(this).balance, ethBalance - oCVEBalance);
        assertEq(address(oCVE).balance, oCVEETHBalance + oCVEBalance);
    }

    function test_exerciseOption_success_withERC20() public {
        oCVEBalance = oCVE.balanceOf(address(this));

        deal(address(cve), address(oCVE), oCVEBalance);
        deal(_USDC_ADDRESS, address(this), oCVEBalance);

        uint256 usdcBalance = usdc.balanceOf(address(this));
        uint256 oCVEUSDCBalance = usdc.balanceOf(address(oCVE));

        usdc.approve(address(oCVE), oCVEBalance);

        vm.expectEmit(true, true, true, true, address(oCVE));
        emit OptionsExercised(address(this), oCVEBalance);

        usdc.allowance(address(this), address(oCVE));

        oCVE.exerciseOption(oCVEBalance);

        assertEq(usdc.balanceOf(address(this)), usdcBalance - oCVEBalance);
        assertEq(usdc.balanceOf(address(oCVE)), oCVEUSDCBalance + oCVEBalance);
    }
}
