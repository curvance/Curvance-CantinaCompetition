pragma solidity ^0.8.17;

import { TestBaseDynamicInterestRateModel } from "../TestBaseDynamicInterestRateModel.sol";
import { DynamicInterestRateModel } from "contracts/market/DynamicInterestRateModel.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract DynamicInterestRateModelDeploymentTest is
    TestBaseDynamicInterestRateModel
{
    function test_dynamicInterestRateModelDeployment_fail_whenCentralRegistryIsInvalid()
        public
    {
        vm.expectRevert(
            DynamicInterestRateModel
                .DynamicInterestRateModel__InvalidCentralRegistry
                .selector
        );
        new DynamicInterestRateModel(
            ICentralRegistry(address(0)),
            1000,
            1000,
            5000,
            12 hours,
            5000,
            100000000,
            100
        );
    }

    function test_dynamicInterestRateModelDeployment_fail_whenAdjustmentVelocityExceedsMaximum()
        public
    {
        uint256 maxVertexAdjustmentVelocity = interestRateModel
            .MAX_VERTEX_ADJUSTMENT_VELOCITY();

        vm.expectRevert(
            DynamicInterestRateModel
                .DynamicInterestRateModel__InvalidAdjustmentVelocity
                .selector
        );
        new DynamicInterestRateModel(
            ICentralRegistry(address(centralRegistry)),
            1000,
            1000,
            5000,
            12 hours,
            (maxVertexAdjustmentVelocity) / 1e14 + 1,
            100000000,
            100
        );
    }

    function test_dynamicInterestRateModelDeployment_fail_whenAdjustmentVelocityIsBelowMinimum()
        public
    {
        uint256 minVertexAdjustmentVelocity = interestRateModel
            .MIN_VERTEX_ADJUSTMENT_VELOCITY();

        vm.expectRevert(
            DynamicInterestRateModel
                .DynamicInterestRateModel__InvalidAdjustmentVelocity
                .selector
        );
        new DynamicInterestRateModel(
            ICentralRegistry(address(centralRegistry)),
            1000,
            1000,
            5000,
            12 hours,
            (minVertexAdjustmentVelocity) / 1e14 - 1,
            100000000,
            100
        );
    }

    function test_dynamicInterestRateModelDeployment_fail_whenAdjustmentRateExceedsMaximum()
        public
    {
        uint256 maxVertexAdjustmentRate = interestRateModel
            .MAX_VERTEX_ADJUSTMENT_RATE();

        vm.expectRevert(
            DynamicInterestRateModel
                .DynamicInterestRateModel__InvalidAdjustmentRate
                .selector
        );
        new DynamicInterestRateModel(
            ICentralRegistry(address(centralRegistry)),
            1000,
            1000,
            5000,
            maxVertexAdjustmentRate + 1,
            5000,
            100000000,
            100
        );
    }

    function test_dynamicInterestRateModelDeployment_fail_whenAdjustmentRateIsBelowMinimum()
        public
    {
        uint256 minVertexAdjustmentRate = interestRateModel
            .MIN_VERTEX_ADJUSTMENT_RATE();

        vm.expectRevert(
            DynamicInterestRateModel
                .DynamicInterestRateModel__InvalidAdjustmentRate
                .selector
        );
        new DynamicInterestRateModel(
            ICentralRegistry(address(centralRegistry)),
            1000,
            1000,
            5000,
            minVertexAdjustmentRate - 1,
            5000,
            100000000,
            100
        );
    }

    function test_dynamicInterestRateModelDeployment_fail_whenDecayRateExceedsMaximum()
        public
    {
        uint256 maxVertexDecayRate = interestRateModel.MAX_VERTEX_DECAY_RATE();

        vm.expectRevert(
            DynamicInterestRateModel
                .DynamicInterestRateModel__InvalidDecayRate
                .selector
        );
        new DynamicInterestRateModel(
            ICentralRegistry(address(centralRegistry)),
            1000,
            1000,
            5000,
            12 hours,
            5000,
            100000000,
            (maxVertexDecayRate / 1e14) + 1
        );
    }

    function test_dynamicInterestRateModelDeployment_fail_whenTheoreticalMultiplierOverflows()
        public
    {
        vm.expectRevert(
            DynamicInterestRateModel
                .DynamicInterestRateModel__InvalidMultiplierMax
                .selector
        );
        new DynamicInterestRateModel(
            ICentralRegistry(address(centralRegistry)),
            1000,
            1000,
            5000,
            12 hours,
            5000,
            type(uint192).max / (1000 * 1e14) / 1e14 + 1,
            100
        );
    }

    function test_dynamicInterestRateModelDeployment_success() public {
        interestRateModel = new DynamicInterestRateModel(
            ICentralRegistry(address(centralRegistry)),
            1500,
            1500,
            5500,
            10 hours,
            5500,
            150000000,
            150
        );
    }
}
