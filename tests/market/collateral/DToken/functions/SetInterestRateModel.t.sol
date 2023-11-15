// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseDToken } from "../TestBaseDToken.sol";
import { DToken } from "contracts/market/collateral/DToken.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";
import { DynamicInterestRateModel } from "contracts/market/interestRates/DynamicInterestRateModel.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract DTokenSetDynamicInterestRateModelTest is TestBaseDToken {
    DynamicInterestRateModel public newDynamicInterestRateModel;

    function setUp() public override {
        super.setUp();

        newDynamicInterestRateModel = new DynamicInterestRateModel(
            ICentralRegistry(address(centralRegistry)),
            0.1e18,
            0.1e18,
            0.5e18
        );
    }

    function test_dTokenSetDynamicInterestRateModel_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.prank(address(1));

        vm.expectRevert(DToken.DToken__Unauthorized.selector);
        dUSDC.setDynamicInterestRateModel(address(newDynamicInterestRateModel));
    }

    function test_dTokenSetDynamicInterestRateModel_fail_whenInvalidDynamicInterestRateModel()
        public
    {
        vm.expectRevert();
        dUSDC.setDynamicInterestRateModel(address(1));
    }

    function test_dTokenSetDynamicInterestRateModel_success() public {
        assertEq(address(dUSDC.interestRateModel()), address(jumpRateModel));

        dUSDC.setDynamicInterestRateModel(address(newDynamicInterestRateModel));

        assertEq(
            address(dUSDC.interestRateModel()),
            address(newDynamicInterestRateModel)
        );
    }
}
