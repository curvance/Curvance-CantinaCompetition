// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/StdStorage.sol";
import { TestBaseDToken } from "../TestBaseDToken.sol";
import { DToken } from "contracts/market/collateral/DToken.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";

contract DTokenDeploymentTest is TestBaseDToken {
    using stdStorage for StdStorage;

    event NewLendtroller(address oldLendtroller, address newLendtroller);

    function test_dTokenDeployment_fail_whenCentralRegistryIsInvalid() public {
        vm.expectRevert(DToken.DToken__CentralRegistryIsInvalid.selector);
        new DToken(
            ICentralRegistry(address(0)),
            _USDC_ADDRESS,
            address(lendtroller),
            address(jumpRateModel)
        );
    }

    function test_dTokenDeployment_fail_whenLendtrollderIsNotLendingMarket()
        public
    {
        vm.expectRevert(DToken.DToken__LendtrollerIsNotLendingMarket.selector);
        new DToken(
            ICentralRegistry(address(centralRegistry)),
            _USDC_ADDRESS,
            address(1),
            address(jumpRateModel)
        );
    }

    function test_dTokenDeployment_fail_whenLendtrollderIsInvalid() public {
        centralRegistry.addLendingMarket(address(1));

        vm.expectRevert(DToken.DToken__LendtrollerIsInvalid.selector);
        new DToken(
            ICentralRegistry(address(centralRegistry)),
            _USDC_ADDRESS,
            address(1),
            address(jumpRateModel)
        );
    }

    function test_dTokenDeployment_fail_whenInterestRateModelIsInvalid()
        public
    {
        vm.expectRevert();
        new DToken(
            ICentralRegistry(address(centralRegistry)),
            _USDC_ADDRESS,
            address(lendtroller),
            address(0)
        );
    }

    function test_dTokenDeployment_fail_whenUnderlyingTotalSupplyExceedsMaximum()
        public
    {
        stdstore
            .target(_USDC_ADDRESS)
            .sig(IERC20.totalSupply.selector)
            .checked_write(type(uint232).max);

        vm.expectRevert("DToken: Underlying token assumptions not met");
        new DToken(
            ICentralRegistry(address(centralRegistry)),
            _USDC_ADDRESS,
            address(lendtroller),
            address(jumpRateModel)
        );
    }

    function test_dTokenDeployment_success() public {
        vm.expectEmit(true, true, true, true);
        emit NewLendtroller(address(0), address(lendtroller));

        dUSDC = new DToken(
            ICentralRegistry(address(centralRegistry)),
            _USDC_ADDRESS,
            address(lendtroller),
            address(jumpRateModel)
        );

        assertEq(address(dUSDC.centralRegistry()), address(centralRegistry));
        assertEq(dUSDC.underlying(), _USDC_ADDRESS);
        assertEq(address(dUSDC.interestRateModel()), address(jumpRateModel));
        assertEq(address(dUSDC.lendtroller()), address(lendtroller));
    }
}
