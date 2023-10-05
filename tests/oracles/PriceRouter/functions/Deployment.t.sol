// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { PriceRouter } from "contracts/oracles/PriceRouter.sol";
import { TestBasePriceRouter } from "../TestBasePriceRouter.sol";

contract PriceRouterDeploymentTest is TestBasePriceRouter {
    function test_priceRouterDeployment_fail_whenCentralRegistryIsInvalid()
        public
    {
        vm.expectRevert(0xebd2e1ff);
        new PriceRouter(ICentralRegistry(address(1)), _CHAINLINK_ETH_USD);
    }

    function test_priceRouterDeployment_fail_whenEthUsdFeedIsZeroAddress()
        public
    {
        vm.expectRevert(0xebd2e1ff);
        new PriceRouter(
            ICentralRegistry(address(centralRegistry)),
            address(0)
        );
    }

    function test_priceRouterDeployment_success() public {
        priceRouter = new PriceRouter(
            ICentralRegistry(address(centralRegistry)),
            _CHAINLINK_ETH_USD
        );

        assertEq(
            address(priceRouter.centralRegistry()),
            address(centralRegistry)
        );
        assertEq(priceRouter.CHAINLINK_ETH_USD(), _CHAINLINK_ETH_USD);
    }
}
