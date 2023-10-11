// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseFeeAccumulator } from "../TestBaseFeeAccumulator.sol";
import { FeeAccumulator } from "contracts/architecture/FeeAccumulator.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract FeeAccumulatorDeploymentTest is TestBaseFeeAccumulator {
    function test_feeAccumulatorDeployment_fail_whenCentralRegistryIsInvalid()
        public
    {
        vm.expectRevert(
            FeeAccumulator.FeeAccumulator__ConfigurationError.selector
        );
        new FeeAccumulator(ICentralRegistry(address(0)), _USDC_ADDRESS, 0, 0);
    }

    function test_feeAccumulatorDeployment_fail_whenFeeTokenIsZeroAddress()
        public
    {
        vm.expectRevert(
            FeeAccumulator.FeeAccumulator__FeeTokenIsZeroAddress.selector
        );
        new FeeAccumulator(
            ICentralRegistry(address(centralRegistry)),
            address(0),
            0,
            0
        );
    }

    function test_feeAccumulatorDeployment_success() public {
        feeAccumulator = new FeeAccumulator(
            ICentralRegistry(address(centralRegistry)),
            _USDC_ADDRESS,
            0,
            0
        );

        assertEq(
            address(feeAccumulator.centralRegistry()),
            address(centralRegistry)
        );
        assertEq(
            address(feeAccumulator.getPriceRouter()),
            centralRegistry.priceRouter()
        );
        assertEq(feeAccumulator.feeToken(), _USDC_ADDRESS);
        assertEq(
            address(feeAccumulator.gelatoOneBalance()),
            centralRegistry.daoAddress()
        );
        assertEq(
            usdc.allowance(
                address(feeAccumulator),
                centralRegistry.protocolMessagingHub()
            ),
            type(uint256).max
        );
        assertEq(
            feeAccumulator.vaultCompoundFee(),
            centralRegistry.protocolCompoundFee()
        );
        assertEq(
            feeAccumulator.vaultYieldFee(),
            centralRegistry.protocolYieldFee()
        );
    }
}
