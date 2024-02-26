// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TestBaseMarketManager } from "../TestBaseMarketManager.sol";
import { MarketManager } from "contracts/market/MarketManager.sol";

contract listTokenTest is TestBaseMarketManager {
    event TokenListed(address mToken);

    function test_listToken_fail_whenCallerIsNotAuthorized() public {
        vm.prank(address(1));

        vm.expectRevert(MarketManager.MarketManager__Unauthorized.selector);
        marketManager.listToken(address(dUSDC));
    }

    function test_listToken_fail_whenMTokenIsAlreadyListed() public {
        marketManager.listToken(address(dUSDC));

        vm.expectRevert(MarketManager.MarketManager__InvalidParameter.selector);
        marketManager.listToken(address(dUSDC));
    }

    function test_listToken_fail_whenMTokenIsInvalid() public {
        vm.expectRevert();
        marketManager.listToken(address(1));
    }

    function test_listToken_success() public {
        (bool isListed, uint256 collRatio, , , , , , , ) = marketManager
            .tokenData(address(dUSDC));
        assertFalse(isListed);
        assertEq(collRatio, 0);

        vm.expectEmit(true, true, true, true, address(marketManager));
        emit TokenListed(address(dUSDC));

        marketManager.listToken(address(dUSDC));

        (isListed, collRatio, , , , , , , ) = marketManager.tokenData(
            address(dUSDC)
        );
        assertTrue(isListed);
        assertEq(collRatio, 0);

        assertEq(dUSDC.totalSupply(), 42069);
    }
}
