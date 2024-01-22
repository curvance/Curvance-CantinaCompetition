// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/StdStorage.sol";
import { TestBaseCTokenCompounding } from "../TestBaseCTokenCompoundingBase.sol";
import { CTokenCompounding } from "contracts/market/collateral/CTokenCompounding.sol";
import { CTokenBase } from "contracts/market/collateral/CTokenBase.sol";
import { AuraCToken } from "contracts/market/collateral/AuraCToken.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";

contract CTokenCompounding_DeploymentTest is TestBaseCTokenCompounding {
    using stdStorage for StdStorage;

    event NewMarketManager(address oldMarketManager, address newMarketManager);

    function test_CTokenCompoundingDeployment_fail_whenCentralRegistryIsInvalid()
        public
    {
        vm.expectRevert(
            CTokenBase.CTokenBase__InvalidCentralRegistry.selector
        );
        new AuraCToken(
            ICentralRegistry(address(0)),
            IERC20(_BALANCER_WETH_RETH),
            address(marketManager),
            109,
            _REWARDER,
            _AURA_BOOSTER
        );
    }

    function test_CTokenCompoundingDeployment_fail_whenMarketManagerIsNotSet()
        public
    {
        vm.expectRevert(
            CTokenBase.CTokenBase__MarketManagerIsNotLendingMarket.selector
        );
        new AuraCToken(
            ICentralRegistry(address(centralRegistry)),
            IERC20(_BALANCER_WETH_RETH),
            address(1),
            109,
            _REWARDER,
            _AURA_BOOSTER
        );
    }

    function test_CTokenCompoundingDeployment_fail_whenUnderlyingTotalSupplyExceedsMaximum()
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
        new AuraCToken(
            ICentralRegistry(address(centralRegistry)),
            IERC20(_BALANCER_WETH_RETH),
            address(marketManager),
            109,
            _REWARDER,
            _AURA_BOOSTER
        );
    }

    function test_CTokenCompoundingDeployment_success() public {
        cBALRETH = new AuraCToken(
            ICentralRegistry(address(centralRegistry)),
            IERC20(_BALANCER_WETH_RETH),
            address(marketManager),
            109,
            _REWARDER,
            _AURA_BOOSTER
        );

        assertEq(
            address(cBALRETH.centralRegistry()),
            address(centralRegistry)
        );
        assertEq(cBALRETH.underlying(), _BALANCER_WETH_RETH);
        assertEq(address(cBALRETH.marketManager()), address(marketManager));
        assertEq(
            cBALRETH.name(),
            "Curvance collateralized Balancer rETH Stable Pool"
        );
    }
}
