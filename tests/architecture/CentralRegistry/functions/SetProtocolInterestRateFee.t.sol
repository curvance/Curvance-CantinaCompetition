// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { CentralRegistry } from "contracts/architecture/CentralRegistry.sol";

contract Market {
    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        if (interfaceId == 0xffffffff) {
            return false;
        }
        return true;
    }
}

contract SetProtocolInterestRateFeeTest is TestBaseMarket {
    address newMarket;

    function setUp() public virtual override {
        super.setUp();
        newMarket = address(new Market());
    }

    function test_setProtocolInterestRateFee_fail_whenUnauthorized() public {
        vm.startPrank(address(0));
        vm.expectRevert(
            CentralRegistry.CentralRegistry__Unauthorized.selector
        );
        centralRegistry.setProtocolInterestRateFee(newMarket, 100);
        vm.stopPrank();
    }

    function test_setProtocolInterestRateFee_fail_whenValueTooHigh() public {
        vm.expectRevert(
            CentralRegistry.CentralRegistry__ParametersMisconfigured.selector
        );
        centralRegistry.setProtocolInterestRateFee(newMarket, 5001);
    }

    function test_setProtocolInterestRateFee_fail_whenNotLendingMarket()
        public
    {
        vm.expectRevert(
            CentralRegistry.CentralRegistry__ParametersMisconfigured.selector
        );
        centralRegistry.setProtocolInterestRateFee(newMarket, 5000);

        centralRegistry.addMarketManager(newMarket, 5000);
        centralRegistry.setProtocolInterestRateFee(newMarket, 5000);
    }

    function test_setProtocolInterestRateFee_success() public {
        centralRegistry.addMarketManager(newMarket, 5000);
        centralRegistry.setProtocolInterestRateFee(newMarket, 5000);
        assertEq(
            centralRegistry.protocolInterestFactor(newMarket),
            5000 * 1e14
        );
    }
}
