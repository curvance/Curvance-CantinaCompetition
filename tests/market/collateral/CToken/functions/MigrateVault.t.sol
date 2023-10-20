// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseCToken } from "../TestBaseCToken.sol";
import { AuraPositionVault } from "contracts/deposits/adaptors/AuraPositionVault.sol";
import { ERC20 } from "contracts/libraries/ERC20.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { CToken } from "contracts/market/collateral/CToken.sol";
import { BasePositionVault } from "contracts/deposits/adaptors/BasePositionVault.sol";

contract MigrateVaultTest is TestBaseCToken {
    event MigrateVault(address oldVault, address newVault);

    AuraPositionVault public newVault;

    function setUp() public override {
        super.setUp();

        newVault = new AuraPositionVault(
            ERC20(_BALANCER_WETH_RETH),
            ICentralRegistry(address(centralRegistry)),
            109,
            _REWARDER,
            _AURA_BOOSTER
        );
    }

    function test_migrateVault_fail_whenCallerIsNotAuthorized() public {
        vm.prank(user1);

        vm.expectRevert(CToken.CToken__Unauthorized.selector);
        cBALRETH.migrateVault(address(newVault));
    }

    function test_migrateVault_fail_whenNewVaultIsNotInitalized() public {
        vm.expectRevert(
            BasePositionVault.BasePositionVault__Unauthorized.selector
        );
        cBALRETH.migrateVault(address(newVault));
    }

    function test_migrateVault_success() public {
        newVault.initiateVault(address(cBALRETH));

        assertEq(address(cBALRETH.vault()), address(vault));

        vm.expectEmit(true, true, true, true, address(cBALRETH));
        emit MigrateVault(address(vault), address(newVault));

        cBALRETH.migrateVault(address(newVault));

        assertEq(address(cBALRETH.vault()), address(newVault));
    }
}
