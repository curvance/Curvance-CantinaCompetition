// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseMarketManager } from "../TestBaseMarketManager.sol";
import { MarketManager } from "contracts/market/MarketManager.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract MarketManagerDeploymentTest is TestBaseMarketManager {
    function test_marketManagerDeployment_fail_whenCentralRegistryIsInvalid()
        public
    {
        // revert LiquidityManager__InvalidParameter()
        vm.expectRevert(0x78eefdcc);
        new MarketManager(ICentralRegistry(address(0)), address(gaugePool));
    }

    function test_marketManagerDeployment_fail_whenGaugePoolIsZeroAddress()
        public
    {
        vm.expectRevert(MarketManager.MarketManager__InvalidParameter.selector);
        new MarketManager(
            ICentralRegistry(address(centralRegistry)),
            address(0)
        );
    }

    function test_marketManagerDeployment_success() public {
        marketManager = new MarketManager(
            ICentralRegistry(address(centralRegistry)),
            address(gaugePool)
        );

        assertEq(address(dUSDC.centralRegistry()), address(centralRegistry));
    }
}
