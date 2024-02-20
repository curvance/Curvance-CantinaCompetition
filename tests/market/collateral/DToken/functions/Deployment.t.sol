// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/StdStorage.sol";
import { TestBaseDToken } from "../TestBaseDToken.sol";
import { DToken } from "contracts/market/collateral/DToken.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { Delegable } from "contracts/libraries/Delegable.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";

contract DTokenDeploymentTest is TestBaseDToken {
    using stdStorage for StdStorage;
    event NewInterestFactor(
        uint256 oldInterestFactor,
        uint256 newInterestFactor
    );

    function test_dTokenDeployment_fail_whenCentralRegistryIsInvalid() public {
        vm.expectRevert(Delegable.Delegable__InvalidCentralRegistry.selector);
        new DToken(
            ICentralRegistry(address(0)),
            _USDC_ADDRESS,
            address(marketManager),
            address(interestRateModel)
        );
    }

    function test_dTokenDeployment_fail_whenMarketManagerIsNotSet() public {
        vm.expectRevert(
            DToken.DToken__MarketManagerIsNotLendingMarket.selector
        );
        new DToken(
            ICentralRegistry(address(centralRegistry)),
            _USDC_ADDRESS,
            address(1),
            address(interestRateModel)
        );
    }

    function test_dTokenDeployment_fail_whenInterestRateModelIsInvalid()
        public
    {
        vm.expectRevert();
        new DToken(
            ICentralRegistry(address(centralRegistry)),
            _USDC_ADDRESS,
            address(marketManager),
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

        vm.expectRevert(
            DToken.DToken__UnderlyingAssetTotalSupplyExceedsMaximum.selector
        );
        new DToken(
            ICentralRegistry(address(centralRegistry)),
            _USDC_ADDRESS,
            address(marketManager),
            address(interestRateModel)
        );
    }

    function test_dTokenDeployment_success() public {
        vm.expectEmit(true, true, true, true);
        uint256 newInterestFactor = centralRegistry.protocolInterestFactor(
            address(marketManager)
        );
        emit NewInterestFactor(0, newInterestFactor);

        dUSDC = new DToken(
            ICentralRegistry(address(centralRegistry)),
            _USDC_ADDRESS,
            address(marketManager),
            address(interestRateModel)
        );

        assertEq(address(dUSDC.centralRegistry()), address(centralRegistry));
        assertEq(dUSDC.underlying(), _USDC_ADDRESS);
        assertEq(
            address(dUSDC.interestRateModel()),
            address(interestRateModel)
        );
        assertEq(address(dUSDC.marketManager()), address(marketManager));
    }
}
