// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { TestBaseOracleRouter } from "../TestBaseOracleRouter.sol";
import { OracleRouter } from "contracts/oracles/OracleRouter.sol";

contract OracleRouterDeploymentTest is TestBaseOracleRouter {
    function test_oracleRouterDeployment_fail_whenCentralRegistryIsInvalid()
        public
    {
        vm.expectRevert(OracleRouter.OracleRouter__InvalidParameter.selector);
        new OracleRouter(ICentralRegistry(address(1)), _CHAINLINK_ETH_USD);
    }

    function test_oracleRouterDeployment_fail_whenEthUsdFeedIsZeroAddress()
        public
    {
        vm.expectRevert(OracleRouter.OracleRouter__InvalidParameter.selector);
        new OracleRouter(
            ICentralRegistry(address(centralRegistry)),
            address(0)
        );
    }

    function test_oracleRouterDeployment_success() public {
        oracleRouter = new OracleRouter(
            ICentralRegistry(address(centralRegistry)),
            _CHAINLINK_ETH_USD
        );

        assertEq(
            address(oracleRouter.centralRegistry()),
            address(centralRegistry)
        );
        assertEq(oracleRouter.CHAINLINK_ETH_USD(), _CHAINLINK_ETH_USD);
    }
}
