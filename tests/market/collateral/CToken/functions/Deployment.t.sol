// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/StdStorage.sol";
import { TestBaseCToken } from "../TestBaseCToken.sol";
import { CToken } from "contracts/market/collateral/CToken.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";

contract CTokenDeploymentTest is TestBaseCToken {
    using stdStorage for StdStorage;

    event NewLendtroller(address oldLendtroller, address newLendtroller);

    function test_cTokenDeployment_fail_whenCentralRegistryIsInvalid() public {
        vm.expectRevert(CToken.CToken__CentralRegistryIsInvalid.selector);
        new CToken(
            ICentralRegistry(address(0)),
            _BALANCER_WETH_RETH,
            address(lendtroller),
            address(0)
        );
    }

    function test_cTokenDeployment_fail_whenLendtrollerIsNotSet()
        public
    {
        vm.expectRevert(CToken.CToken__LendtrollerIsNotLendingMarket.selector);
        new CToken(
            ICentralRegistry(address(centralRegistry)),
            _BALANCER_WETH_RETH,
            address(1),
            address(0)
        );
    }

    function test_cTokenDeployment_fail_whenLendtrollerIsNotLendingMarket() public {
        centralRegistry.addLendingMarket(address(1));

        vm.expectRevert(CToken.CToken__LendtrollerIsNotLendingMarket.selector);
        new CToken(
            ICentralRegistry(address(centralRegistry)),
            _BALANCER_WETH_RETH,
            address(1),
            address(0)
        );
    }

    function test_cTokenDeployment_fail_whenUnderlyingTotalSupplyExceedsMaximum()
        public
    {
        stdstore
            .target(_BALANCER_WETH_RETH)
            .sig(IERC20.totalSupply.selector)
            .checked_write(type(uint232).max);

        vm.expectRevert("CToken: Underlying token assumptions not met");
        new CToken(
            ICentralRegistry(address(centralRegistry)),
            _BALANCER_WETH_RETH,
            address(lendtroller),
            address(0)
        );
    }

    function test_cTokenDeployment_success() public {
        vm.expectEmit(true, true, true, true);
        emit NewLendtroller(address(0), address(lendtroller));

        cBALRETH = new CToken(
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
