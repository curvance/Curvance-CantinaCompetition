// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseLendtroller } from "../TestBaseLendtroller.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract LendtrollerDeploymentTest is TestBaseLendtroller {
    function test_lendtrollerDeployment_fail_whenCentralRegistryIsInvalid()
        public
    {
        vm.expectRevert(Lendtroller.Lendtroller__InvalidParameter.selector);
        new Lendtroller(ICentralRegistry(address(0)), address(gaugePool));
    }

    function test_lendtrollerDeployment_fail_whenGaugePoolIsZeroAddress()
        public
    {
        vm.expectRevert(Lendtroller.Lendtroller__InvalidParameter.selector);
        new Lendtroller(
            ICentralRegistry(address(centralRegistry)),
            address(0)
        );
    }

    function test_lendtrollerDeployment_success() public {
        lendtroller = new Lendtroller(
            ICentralRegistry(address(centralRegistry)),
            address(gaugePool)
        );

        assertEq(address(dUSDC.centralRegistry()), address(centralRegistry));
        assertEq(dUSDC.gaugePool(), address(gaugePool));
        assertEq(
            address(lendtroller.getPriceRouter()),
            centralRegistry.priceRouter()
        );
    }
}
