// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseDToken } from "../TestBaseDToken.sol";
import { DToken } from "contracts/market/collateral/DToken.sol";
import { MarketManager } from "contracts/market/MarketManager.sol";
import { DynamicInterestRateModel } from "contracts/market/DynamicInterestRateModel.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract DTokenSetInterestRateModelTest is TestBaseDToken {
    DynamicInterestRateModel public newDynamicInterestRateModel;

    function setUp() public override {
        super.setUp();

        newDynamicInterestRateModel = new DynamicInterestRateModel(
            ICentralRegistry(address(centralRegistry)),
            1000, // baseRatePerYear
            1000, // vertexRatePerYear
            5000, // vertexUtilizationStart
            12 hours, // adjustmentRate
            5000, // adjustmentVelocity
            100000000, // 1000x maximum vertex multiplier
            100 // decayRate
        );
    }

    function test_dTokenSetDynamicInterestRateModel_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.prank(address(1));

        vm.expectRevert(DToken.DToken__Unauthorized.selector);
        dUSDC.setInterestRateModel(address(newDynamicInterestRateModel));
    }

    function test_dTokenSetDynamicInterestRateModel_fail_whenInvalidDynamicInterestRateModel()
        public
    {
        vm.expectRevert();
        dUSDC.setInterestRateModel(address(1));
    }

    function test_dTokenSetDynamicInterestRateModel_success() public {
        assertEq(
            address(dUSDC.interestRateModel()),
            address(interestRateModel)
        );

        dUSDC.setInterestRateModel(address(newDynamicInterestRateModel));

        assertEq(
            address(dUSDC.interestRateModel()),
            address(newDynamicInterestRateModel)
        );
    }
}
