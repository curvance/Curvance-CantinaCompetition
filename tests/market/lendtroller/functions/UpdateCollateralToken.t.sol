// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseLendtroller } from "../TestBaseLendtroller.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";
import { IMToken } from "contracts/interfaces/market/IMToken.sol";

contract UpdateCollateralTokenTest is TestBaseLendtroller {
    event CollateralTokenUpdated(
        IMToken mToken,
        uint256 newLI,
        uint256 newLF,
        uint256 newCR_A,
        uint256 newCR_B,
        uint256 newCR
    );

    function test_updateCollateralToken_fail_whenNotCToken() public {
        vm.expectRevert(Lendtroller.Lendtroller__InvalidParameter.selector);
        lendtroller.updateCollateralToken(
            IMToken(address(dUSDC)),
            200,
            0,
            300,
            250,
            9100 + 1
        );
    }

    function test_updateCollateralToken_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.prank(address(1));

        vm.expectRevert(Lendtroller.Lendtroller__Unauthorized.selector);
        lendtroller.updateCollateralToken(
            IMToken(address(dUSDC)),
            200,
            0,
            300,
            250,
            9000
        );
    }

    function test_updateCollateralToken_fail_whenLiqIncentiveExceedsMax()
        public
    {
        // when liqInc > _MAX_LIQUIDATION_INCENTIVE
        lendtroller.listToken(address(cBALRETH));
        vm.expectRevert(Lendtroller.Lendtroller__InvalidParameter.selector);
        lendtroller.updateCollateralToken(
            IMToken(address(cBALRETH)),
            3100, // liqInc
            0,
            300,
            250,
            9100 + 1
        );
    }

    function test_updateCollateralToken_fail_whenLiqFeeExceedsMax() public {
        // when liqFee > _MAX_LIQUIDATION_FEE
        lendtroller.listToken(address(cBALRETH));
        vm.expectRevert(Lendtroller.Lendtroller__InvalidParameter.selector);
        lendtroller.updateCollateralToken(
            IMToken(address(cBALRETH)),
            3000,
            600, // liqFee
            300,
            250,
            9100 + 1
        );
    }

    function test_updateCollateralToken_fail_whenCollReqAExceedsMax() public {
        // when collReqA > _MAX_COLLATERAL_REQUIREMENT
        lendtroller.listToken(address(cBALRETH));
        vm.expectRevert(Lendtroller.Lendtroller__InvalidParameter.selector);
        lendtroller.updateCollateralToken(
            IMToken(address(cBALRETH)),
            3000,
            500,
            4100, // collReqA
            250,
            9100 + 1
        );
    }

    function test_updateCollateralToken_fail_whenHardCollReqExceedsSoftCollReq()
        public
    {
        // when collReqB > collReqA
        lendtroller.listToken(address(cBALRETH));
        vm.expectRevert(Lendtroller.Lendtroller__InvalidParameter.selector);
        lendtroller.updateCollateralToken(
            IMToken(address(cBALRETH)),
            3000,
            500,
            4000, // collReqA - soft liquidation requirement
            4100, // collReqB - hard liquidation requirement
            9100 + 1
        );
    }

    function test_updateCollateralToken_fail_whenCollRatioExceedsMax() public {
        // when collRatio > _MAX_COLLATERALIZATION_RATIO
        lendtroller.listToken(address(cBALRETH));
        vm.expectRevert(Lendtroller.Lendtroller__InvalidParameter.selector);
        lendtroller.updateCollateralToken(
            IMToken(address(cBALRETH)),
            3000,
            500,
            4000,
            3000,
            9100 + 1 // collRatio
        );
    }

    function test_updateCollateralToken_fail_whenCollRatioExceedsPremium()
        public
    {
        // when collRatio > (EXP_SCALE * EXP_SCALE) / (EXP_SCALE + collReqA)
        lendtroller.listToken(address(cBALRETH));
        vm.expectRevert(Lendtroller.Lendtroller__InvalidParameter.selector);
        lendtroller.updateCollateralToken(
            IMToken(address(cBALRETH)),
            3000,
            500,
            4000,
            3000,
            9100 // collRatio
        );
    }

    function test_updateCollateralToken_fail_whenLiqIncExceedsHardLiquidationRequirement()
        public
    {
        // when liqInc > collReqB
        lendtroller.listToken(address(cBALRETH));
        vm.expectRevert(Lendtroller.Lendtroller__InvalidParameter.selector);
        lendtroller.updateCollateralToken(
            IMToken(address(cBALRETH)),
            3000, // liqInc
            500,
            4000,
            2900, // collReqB
            7000
        );
    }

    function test_updateCollateralToken_fail_whenLiqIncNotEnough() public {
        // when (liqInc - liqFee) < _MIN_LIQUIDATION_INCENTIVE
        lendtroller.listToken(address(cBALRETH));
        vm.expectRevert(Lendtroller.Lendtroller__InvalidParameter.selector);
        lendtroller.updateCollateralToken(
            IMToken(address(cBALRETH)),
            550, // liqInc
            500, // liqFee
            4000,
            2900,
            7000
        );
    }

    function test_updateCollateralToken_fail_whenMTokenIsNotListed() public {
        vm.expectRevert(Lendtroller.Lendtroller__TokenNotListed.selector);
        lendtroller.updateCollateralToken(
            IMToken(address(cBALRETH)),
            200,
            0,
            300,
            250,
            9000
        );
    }

    function test_updateCollateralToken_fail_whenPriceRouterFails() public {
        // Set Oracle timestamp to 0 to make price stale
        chainlinkEthUsd.updateRoundData(0, 1e8, 0, 0);

        lendtroller.listToken(address(cBALRETH));
        vm.expectRevert(Lendtroller.Lendtroller__PriceError.selector);
        lendtroller.updateCollateralToken(
            IMToken(address(cBALRETH)),
            3000,
            500,
            4000,
            3000,
            7000
        );
    }

    function test_updateCollateralToken_success() public {
        balRETH.approve(address(cBALRETH), 1e18);
        lendtroller.listToken(address(cBALRETH));

        vm.expectEmit(true, true, true, true, address(lendtroller));
        emit CollateralTokenUpdated(
            IMToken(address(cBALRETH)),
            0.02e18,
            0,
            0.03e18,
            0.025e18,
            0.9e18
        );

        lendtroller.updateCollateralToken(
            IMToken(address(cBALRETH)),
            200,
            0,
            300,
            250,
            9000
        );

        (, , uint256 collateralizationRatio) = lendtroller.getTokenData(
            address(cBALRETH)
        );
        assertEq(collateralizationRatio, 0.9e18);
    }
}
