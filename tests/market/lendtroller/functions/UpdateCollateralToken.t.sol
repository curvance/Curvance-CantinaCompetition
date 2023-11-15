// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseLendtroller } from "../TestBaseLendtroller.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";
import { IMToken } from "contracts/interfaces/market/IMToken.sol";

contract UpdateCollateralTokenTest is TestBaseLendtroller {
    event CollateralTokenUpdated(
        IMToken mToken,
        uint256 collRatio,
        uint256 collReqA,
        uint256 collReqB,
        uint256 liqIncA,
        uint256 liqIncB,
        uint256 liqFee,
        uint256 baseCFactor
    );

    function test_updateCollateralToken_fail_whenNotCToken() public {
        vm.expectRevert(Lendtroller.Lendtroller__InvalidParameter.selector);
        lendtroller.updateCollateralToken(
            IMToken(address(dUSDC)),
            9100 + 1,
            200,
            300,
            250,
            250,
            0,
            1000
        );
    }

    function test_updateCollateralToken_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.prank(address(1));

        vm.expectRevert(Lendtroller.Lendtroller__Unauthorized.selector);
        lendtroller.updateCollateralToken(
            IMToken(address(dUSDC)),
            9000,
            200,
            300,
            250,
            250,
            0,
            1000
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
            9000,
            200,
            300,
            3100, // liqIncA
            250,
            0,
            1000
        );
    }

    function test_updateCollateralToken_fail_whenLiqFeeExceedsMax() public {
        // when liqFee > _MAX_LIQUIDATION_FEE
        lendtroller.listToken(address(cBALRETH));
        vm.expectRevert(Lendtroller.Lendtroller__InvalidParameter.selector);
        lendtroller.updateCollateralToken(
            IMToken(address(cBALRETH)),
            9000,
            200,
            300,
            250,
            250,
            600, // liqFee
            1000
        );
    }

    function test_updateCollateralToken_fail_whenCollReqAExceedsMax() public {
        // when collReqA > _MAX_COLLATERAL_REQUIREMENT
        lendtroller.listToken(address(cBALRETH));
        vm.expectRevert(Lendtroller.Lendtroller__InvalidParameter.selector);
        lendtroller.updateCollateralToken(
            IMToken(address(cBALRETH)),
            9000,
            4100, // collReqA
            300,
            250,
            250,
            0,
            1000
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
            9000,
            4000, // collReqA - soft liquidation requirement
            4100,
            250,
            250,
            0,
            1000
        );
    }

    function test_updateCollateralToken_fail_whenCollRatioExceedsMax() public {
        // when collRatio > _MAX_COLLATERALIZATION_RATIO
        lendtroller.listToken(address(cBALRETH));
        vm.expectRevert(Lendtroller.Lendtroller__InvalidParameter.selector);
        lendtroller.updateCollateralToken(
            IMToken(address(cBALRETH)),
            9101, // collRatio
            200,
            300,
            250,
            250,
            0,
            1000
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
            9100, // collRatio
            4000,
            3000,
            250,
            250,
            0,
            1000
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
            7000,
            200,
            2900,
            3000,
            250,
            0,
            1000
        );
    }

    function test_updateCollateralToken_fail_whenLiqIncNotEnough() public {
        // when (liqInc - liqFee) < _MIN_LIQUIDATION_INCENTIVE
        lendtroller.listToken(address(cBALRETH));
        vm.expectRevert(Lendtroller.Lendtroller__InvalidParameter.selector);
        lendtroller.updateCollateralToken(
            IMToken(address(cBALRETH)),
            9100,
            200,
            300,
            550, // liqIncA
            500, // liqIncB
            500, // liqFee
            1000
        );
    }

    function test_updateCollateralToken_fail_whenMTokenIsNotListed() public {
        vm.expectRevert(Lendtroller.Lendtroller__TokenNotListed.selector);
        lendtroller.updateCollateralToken(
            IMToken(address(cBALRETH)),
            9100,
            300,
            200,
            200,
            150,
            0,
            1000
        );
    }

    function test_updateCollateralToken_fail_whenPriceRouterFails() public {
        // Set Oracle timestamp to 0 to make price stale
        chainlinkEthUsd.updateRoundData(0, 1e8, 0, 0);

        lendtroller.listToken(address(cBALRETH));
        vm.expectRevert(Lendtroller.Lendtroller__PriceError.selector);
        lendtroller.updateCollateralToken(
            IMToken(address(cBALRETH)),
            9100, // collRatio
            300,
            200,
            200,
            250,
            0,
            1000
        );
    }

    function test_updateCollateralToken_success() public {
        balRETH.approve(address(cBALRETH), 1e18);
        lendtroller.listToken(address(cBALRETH));

        vm.expectEmit(true, true, true, true, address(lendtroller));
        emit CollateralTokenUpdated(
            IMToken(address(cBALRETH)),
            0.91e18,
            0.03e18,
            0.02e18,
            0.02e18,
            0.025e18,
            0,
            0.1e18
        );

        lendtroller.updateCollateralToken(
            IMToken(address(cBALRETH)),
            9100,
            300,
            200,
            200,
            250,
            0,
            1000
        );

        (, uint256 collRatio, , , , , , , ) = lendtroller.tokenData(
            address(cBALRETH)
        );
        assertEq(collRatio, 0.91e18);
    }
}
