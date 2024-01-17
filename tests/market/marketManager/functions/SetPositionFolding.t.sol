// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseMarketManager } from "../TestBaseMarketManager.sol";
import { MarketManager } from "contracts/market/MarketManager.sol";

contract SetPositionFoldingTest is TestBaseMarketManager {
    event NewPositionFoldingContract(address oldPF, address newPF);

    function test_setPositionFolding_fail_whenCallerIsNotAuthorized() public {
        vm.prank(address(1));

        vm.expectRevert(MarketManager.MarketManager__Unauthorized.selector);
        marketManager.setPositionFolding(address(positionFolding));
    }

    function test_setPositionFolding_fail_whenPositionFoldingIsInvalid()
        public
    {
        vm.expectRevert(MarketManager.MarketManager__InvalidParameter.selector);
        marketManager.setPositionFolding(address(1));
    }

    function test_setPositionFolding_success() public {
        address oldPositionFolding = marketManager.positionFolding();

        _deployPositionFolding();

        vm.expectEmit(true, true, true, true, address(marketManager));
        emit NewPositionFoldingContract(
            oldPositionFolding,
            address(positionFolding)
        );

        marketManager.setPositionFolding(address(positionFolding));

        assertEq(marketManager.positionFolding(), address(positionFolding));
    }
}
