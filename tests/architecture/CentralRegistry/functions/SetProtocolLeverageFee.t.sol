// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { CentralRegistry } from "contracts/architecture/CentralRegistry.sol";

contract SetProtocolLeverageFeeTest is TestBaseMarket {
    function test_setProtocolLeverageFee_fail_whenUnauthorized() public {
        vm.startPrank(address(0));
        vm.expectRevert(
            CentralRegistry.CentralRegistry__Unauthorized.selector
        );
        centralRegistry.setProtocolLeverageFee(100);
        vm.stopPrank();
    }

    function test_setProtocolLeverageFee_fail_whenParametersMisconfigured()
        public
    {
        vm.expectRevert(
            CentralRegistry.CentralRegistry__ParametersMisconfigured.selector
        );
        centralRegistry.setProtocolLeverageFee(201);

        centralRegistry.setProtocolLeverageFee(200);
    }

    function test_setProtocolLeverageFee_success() public {
        centralRegistry.setProtocolLeverageFee(100);
        assertEq(centralRegistry.protocolLeverageFee(), 100 * 1e14);
    }
}
