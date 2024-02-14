// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/StdStorage.sol";
import { TestBaseCTokenCompoundingWithExitFee } from "../TestBaseCTokenCompoundingWithExitFee.sol";
import { CTokenBase } from "contracts/market/collateral/CTokenBase.sol";
import { MockAuraCTokenWithExitFee } from "contracts/mocks/MockAuraCTokenWithExitFee.sol";
import { CTokenCompoundingWithExitFee } from "contracts/market/collateral/CTokenCompoundingWithExitFee.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";

contract CTokenCompoundingWithExitFeeDeploymentTest is
    TestBaseCTokenCompoundingWithExitFee
{
    using stdStorage for StdStorage;

    event NewMarketManager(address oldMarketManager, address newMarketManager);

    function test_cTokenCompoundingWithExitFeeDeployment_fail_whenCentralRegistryIsInvalid()
        public
    {
        vm.expectRevert(
            CTokenBase.CTokenBase__InvalidCentralRegistry.selector
        );
        new MockAuraCTokenWithExitFee(
            ICentralRegistry(address(0)),
            IERC20(_BALANCER_WETH_RETH),
            address(marketManager),
            109,
            _REWARDER,
            _AURA_BOOSTER,
            200
        );
    }

    function test_cTokenCompoundingWithExitFeeDeployment_fail_whenMarketManagerIsNotSet()
        public
    {
        vm.expectRevert(CTokenBase.CTokenBase__InvalidMarketManager.selector);
        new MockAuraCTokenWithExitFee(
            ICentralRegistry(address(centralRegistry)),
            IERC20(_BALANCER_WETH_RETH),
            address(1),
            109,
            _REWARDER,
            _AURA_BOOSTER,
            200
        );
    }

    function test_cTokenCompoundingWithExitFeeDeployment_fail_whenUnderlyingTotalSupplyExceedsMaximum()
        public
    {
        stdstore
            .target(_BALANCER_WETH_RETH)
            .sig(IERC20.totalSupply.selector)
            .checked_write(type(uint232).max);

        vm.expectRevert(
            CTokenBase
                .CTokenBase__UnderlyingAssetTotalSupplyExceedsMaximum
                .selector
        );
        new MockAuraCTokenWithExitFee(
            ICentralRegistry(address(centralRegistry)),
            IERC20(_BALANCER_WETH_RETH),
            address(marketManager),
            109,
            _REWARDER,
            _AURA_BOOSTER,
            200
        );
    }

    function test_cTokenCompoundingWithExitFeeDeployment_fail_whenExitFeeExceedsMaximum()
        public
    {
        vm.expectRevert(
            CTokenCompoundingWithExitFee
                .CTokenCompoundingWithExitFee__InvalidExitFee
                .selector
        );
        new MockAuraCTokenWithExitFee(
            ICentralRegistry(address(centralRegistry)),
            IERC20(_BALANCER_WETH_RETH),
            address(marketManager),
            109,
            _REWARDER,
            _AURA_BOOSTER,
            201
        );
    }

    function test_cTokenCompoundingWithExitFeeDeployment_success() public {
        cBALRETHWithExitFee = new MockAuraCTokenWithExitFee(
            ICentralRegistry(address(centralRegistry)),
            IERC20(_BALANCER_WETH_RETH),
            address(marketManager),
            109,
            _REWARDER,
            _AURA_BOOSTER,
            200
        );

        assertEq(
            address(cBALRETHWithExitFee.centralRegistry()),
            address(centralRegistry)
        );
        assertEq(cBALRETHWithExitFee.underlying(), _BALANCER_WETH_RETH);
        assertEq(
            address(cBALRETHWithExitFee.marketManager()),
            address(marketManager)
        );
        assertEq(
            cBALRETHWithExitFee.name(),
            "Curvance collateralized Balancer rETH Stable Pool"
        );
        assertEq(cBALRETHWithExitFee.exitFee(), 0.02e18);
    }
}
