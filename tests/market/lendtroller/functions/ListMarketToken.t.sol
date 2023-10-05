// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseLendtroller } from "../TestBaseLendtroller.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";

contract ListMarketTokenTest is TestBaseLendtroller {
    event MarketListed(address mToken);

    function test_listMarketToken_fail_whenCallerIsNotAuthorized() public {
        vm.prank(address(1));

        vm.expectRevert("Lendtroller: UNAUTHORIZED");
        lendtroller.listMarketToken(address(dUSDC));
    }

    function test_listMarketToken_fail_whenMTokenIsAlreadyListed() public {
        lendtroller.listMarketToken(address(dUSDC));

        vm.expectRevert(Lendtroller.Lendtroller__TokenAlreadyListed.selector);
        lendtroller.listMarketToken(address(dUSDC));
    }

    function test_listMarketToken_fail_whenMTokenIsInvalid() public {
        vm.expectRevert();
        lendtroller.listMarketToken(address(1));
    }

    function test_listMarketToken_success() public {
        (bool isListed, , uint256 collateralizationRatio) = lendtroller
            .getMTokenData(address(dUSDC));
        assertFalse(isListed);
        assertEq(collateralizationRatio, 0);

        vm.expectEmit(true, true, true, true, address(lendtroller));
        emit MarketListed(address(dUSDC));

        lendtroller.listMarketToken(address(dUSDC));

        (isListed, , collateralizationRatio) = lendtroller.getMTokenData(
            address(dUSDC)
        );
        assertTrue(isListed);
        assertEq(collateralizationRatio, 0);

        assertEq(dUSDC.totalSupply(), 42069);
    }
}
