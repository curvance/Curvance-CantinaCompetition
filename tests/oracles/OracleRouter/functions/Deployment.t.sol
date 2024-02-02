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
        new OracleRouter(ICentralRegistry(address(1)));
    }

    function test_oracleRouterDeployment_success() public {
        oracleRouter = new OracleRouter(
            ICentralRegistry(address(centralRegistry))
        );

        assertEq(
            address(oracleRouter.centralRegistry()),
            address(centralRegistry)
        );
    }
}
