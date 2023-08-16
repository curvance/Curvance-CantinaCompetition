// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseDToken } from "../TestBaseDToken.sol";
import { DToken } from "contracts/market/collateral/DToken.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";
import { InterestRateModel } from "contracts/market/interestRates/InterestRateModel.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract DTokenSetInterestRateModelTest is TestBaseDToken {
    InterestRateModel public newInterestRateModel;

    function setUp() public override {
        super.setUp();

        newInterestRateModel = new InterestRateModel(
            ICentralRegistry(address(centralRegistry)),
            0.1e18,
            0.1e18,
            0.5e18
        );
    }

    function test_dTokenSetInterestRateModel_fail_whenCallerIsNotAuthorized()
        public
    {
        vm.prank(address(1));

        vm.expectRevert("DToken: UNAUTHORIZED");
        dUSDC.setInterestRateModel(address(newInterestRateModel));
    }

    function test_dTokenSetInterestRateModel_fail_whenInterestRateModelIsInvalid()
        public
    {
        vm.expectRevert();
        dUSDC.setInterestRateModel(address(1));
    }

    function test_dTokenSetInterestRateModel_success() public {
        assertEq(address(dUSDC.interestRateModel()), address(jumpRateModel));

        dUSDC.setInterestRateModel(address(newInterestRateModel));

        assertEq(
            address(dUSDC.interestRateModel()),
            address(newInterestRateModel)
        );
    }
}
