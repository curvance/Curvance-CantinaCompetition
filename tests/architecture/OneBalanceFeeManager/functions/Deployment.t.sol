// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseOneBalanceFeeManager } from "../TestBaseOneBalanceFeeManager.sol";
import { FeeTokenBridgingHub } from "contracts/architecture/FeeTokenBridgingHub.sol";
import { OneBalanceFeeManager } from "contracts/architecture/OneBalanceFeeManager.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract OneBalanceFeeManagerDeploymentTest is TestBaseOneBalanceFeeManager {
    function test_oneBalanceFeeManagerDeployment_fail_whenCentralRegistryIsInvalid()
        public
    {
        vm.expectRevert(
            FeeTokenBridgingHub
                .FeeTokenBridgingHub__InvalidCentralRegistry
                .selector
        );
        new OneBalanceFeeManager(
            ICentralRegistry(address(0)),
            _GELATO_ONE_BALANCE,
            address(1)
        );
    }

    function test_oneBalanceFeeManagerDeployment_fail_whenGelatoOneBalanceIsZeroAddress()
        public
    {
        vm.chainId(137);

        vm.expectRevert(
            OneBalanceFeeManager
                .OneBalanceFeeManager__InvalidGelatoOneBalance
                .selector
        );
        new OneBalanceFeeManager(
            ICentralRegistry(address(centralRegistry)),
            address(0),
            address(1)
        );
    }

    function test_oneBalanceFeeManagerDeployment_fail_whenPolygonOneBalanceFeeManagerIsZeroAddress()
        public
    {
        vm.expectRevert(
            OneBalanceFeeManager
                .OneBalanceFeeManager__InvalidPolygonOneBalanceFeeManager
                .selector
        );
        new OneBalanceFeeManager(
            ICentralRegistry(address(centralRegistry)),
            _GELATO_ONE_BALANCE,
            address(0)
        );
    }

    function test_oneBalanceFeeManagerDeployment_success() public {
        oneBalanceFeeManager = new OneBalanceFeeManager(
            ICentralRegistry(address(centralRegistry)),
            _GELATO_ONE_BALANCE,
            address(1)
        );

        assertEq(
            address(oneBalanceFeeManager.centralRegistry()),
            address(centralRegistry)
        );
        assertEq(
            address(oneBalanceFeeManager.gelatoOneBalance()),
            _GELATO_ONE_BALANCE
        );
        assertEq(
            oneBalanceFeeManager.polygonOneBalanceFeeManager(),
            address(1)
        );
        assertEq(oneBalanceFeeManager.feeToken(), _USDC_ADDRESS);
    }
}
