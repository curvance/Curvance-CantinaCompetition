// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/StdStorage.sol";
import { TestBaseCTokenCompoundingBase } from "../TestBaseCTokenCompoundingBase.sol";
import { CTokenCompoundingBase } from "contracts/market/collateral/CTokenCompoundingBase.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";

contract CTokenCompoundingBase_DeploymentTest is TestBaseCTokenCompoundingBase {
    using stdStorage for StdStorage;

    event NewLendtroller(address oldLendtroller, address newLendtroller);

    function test_CTokenCompoundingBaseDeployment_fail_whenCentralRegistryIsInvalid() public {
        vm.expectRevert(CTokenCompoundingBase.CTokenCompoundingBase__InvalidCentralRegistry.selector);
        new CTokenCompoundingBase(
            ICentralRegistry(address(0)),
            _BALANCER_WETH_RETH,
            address(lendtroller),
            address(0)
        );
    }

    function test_CTokenCompoundingBaseDeployment_fail_whenLendtrollerIsNotSet() public {
        vm.expectRevert(CTokenCompoundingBase.CTokenCompoundingBase__LendtrollerIsNotLendingMarket.selector);
        new CTokenCompoundingBase(
            ICentralRegistry(address(centralRegistry)),
            _BALANCER_WETH_RETH,
            address(1),
            address(0)
        );
    }

    function test_CTokenCompoundingBaseDeployment_fail_whenUnderlyingTotalSupplyExceedsMaximum()
        public
    {
        stdstore
            .target(_BALANCER_WETH_RETH)
            .sig(IERC20.totalSupply.selector)
            .checked_write(type(uint232).max);

        vm.expectRevert(
            CTokenCompoundingBase.CTokenCompoundingBase__UnderlyingAssetTotalSupplyExceedsMaximum.selector
        );
        new CTokenCompoundingBase(
            ICentralRegistry(address(centralRegistry)),
            _BALANCER_WETH_RETH,
            address(lendtroller),
            address(0)
        );
    }

    function test_CTokenCompoundingBaseDeployment_success() public {
        vm.expectEmit(true, true, true, true);
        emit NewLendtroller(address(0), address(lendtroller));

        cBALRETH = new CTokenCompoundingBase(
            ICentralRegistry(address(centralRegistry)),
            _BALANCER_WETH_RETH,
            address(lendtroller),
            address(0)
        );

        assertEq(
            address(cBALRETH.centralRegistry()),
            address(centralRegistry)
        );
        assertEq(cBALRETH.underlying(), _BALANCER_WETH_RETH);
        assertEq(address(cBALRETH.vault()), address(0));
        assertEq(address(cBALRETH.lendtroller()), address(lendtroller));
        //assertEq(cBALRETH.name(), "Curvance collateralized cBAL-WETH-RETH");
    }
}
