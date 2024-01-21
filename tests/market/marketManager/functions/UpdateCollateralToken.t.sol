// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseMarketManager } from "../TestBaseMarketManager.sol";
import { MarketManager } from "contracts/market/MarketManager.sol";
import { IMToken } from "contracts/interfaces/market/IMToken.sol";

contract UpdateCollateralTokenTest is TestBaseMarketManager {
    event CollateralTokenUpdated(
        IMToken mToken,
        uint256 collRatio,
        uint256 CollReqSoft,
        uint256 CollReqHard,
        uint256 liqIncA,
        uint256 liqIncB,
        uint256 liqFee,
        uint256 baseCFactor
    );

    function test_updateCollateralToken_fail_whenNotCToken() public {
        vm.expectRevert(MarketManager.MarketManager__InvalidParameter.selector);
        marketManager.updateCollateralToken(
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

        vm.expectRevert(MarketManager.MarketManager__Unauthorized.selector);
        marketManager.updateCollateralToken(
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
        marketManager.listToken(address(cBALRETH));
        vm.expectRevert(MarketManager.MarketManager__InvalidParameter.selector);
        marketManager.updateCollateralToken(
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
        marketManager.listToken(address(cBALRETH));
        vm.expectRevert(MarketManager.MarketManager__InvalidParameter.selector);
        marketManager.updateCollateralToken(
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

    function test_updateCollateralToken_fail_whenCollReqSoftExceedsMax() public {
        // when CollReqSoft > _MAX_COLLATERAL_REQUIREMENT
        marketManager.listToken(address(cBALRETH));
        vm.expectRevert(MarketManager.MarketManager__InvalidParameter.selector);
        marketManager.updateCollateralToken(
            IMToken(address(cBALRETH)),
            9000,
            23500, // collReqSoft
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
        // when CollReqHard > CollReqSoft
        marketManager.listToken(address(cBALRETH));
        vm.expectRevert(MarketManager.MarketManager__InvalidParameter.selector);
        marketManager.updateCollateralToken(
            IMToken(address(cBALRETH)),
            9000,
            4000, // CollReqSoft - soft liquidation requirement
            4100,
            250,
            250,
            0,
            1000
        );
    }

    function test_updateCollateralToken_fail_whenCollRatioExceedsMax() public {
        // when collRatio > _MAX_COLLATERALIZATION_RATIO
        marketManager.listToken(address(cBALRETH));
        vm.expectRevert(MarketManager.MarketManager__InvalidParameter.selector);
        marketManager.updateCollateralToken(
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
        // when collRatio > (EXP_SCALE * EXP_SCALE) / (EXP_SCALE + CollReqSoft)
        marketManager.listToken(address(cBALRETH));
        vm.expectRevert(MarketManager.MarketManager__InvalidParameter.selector);
        marketManager.updateCollateralToken(
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
        // when liqInc > CollReqHard
        marketManager.listToken(address(cBALRETH));
        vm.expectRevert(MarketManager.MarketManager__InvalidParameter.selector);
        marketManager.updateCollateralToken(
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
        marketManager.listToken(address(cBALRETH));
        vm.expectRevert(MarketManager.MarketManager__InvalidParameter.selector);
        marketManager.updateCollateralToken(
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
        vm.expectRevert(MarketManager.MarketManager__TokenNotListed.selector);
        marketManager.updateCollateralToken(
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

    function test_updateCollateralToken_fail_whenOracleRouterFails() public {
        // Set Oracle timestamp to 0 to make price stale
        mockRethFeed.setMockUpdatedAt(1);

        marketManager.listToken(address(cBALRETH));
        vm.expectRevert(MarketManager.MarketManager__PriceError.selector);
        marketManager.updateCollateralToken(
            IMToken(address(cBALRETH)),
            7000, // collRatio
            4000,
            3000,
            200,
            400,
            10,
            1000
        );
    }

    function test_updateCollateralToken_success() public {
        balRETH.approve(address(cBALRETH), 1e18);
        marketManager.listToken(address(cBALRETH));

        vm.expectEmit(true, true, true, true, address(marketManager));
        emit CollateralTokenUpdated(
            IMToken(address(cBALRETH)),
            0.7e18,
            0.4e18,
            0.3e18,
            0.02e18,
            0.04e18,
            0.001e18,
            0.1e18
        );

        marketManager.updateCollateralToken(
            IMToken(address(cBALRETH)),
            7000, // collRatio
            4000,
            3000,
            200,
            400,
            10,
            1000
        );

        (, uint256 collRatio, , , , , , , ) = marketManager.tokenData(
            address(cBALRETH)
        );
        assertEq(collRatio, 0.7e18);
    }
}
