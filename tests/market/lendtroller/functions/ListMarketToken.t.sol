// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseLendtroller } from "../TestBaseLendtroller.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";

contract listTokenTest is TestBaseLendtroller {
    event MarketListed(address mToken);

    function test_listToken_fail_whenCallerIsNotAuthorized() public {
        vm.prank(address(1));

        vm.expectRevert(Lendtroller.Lendtroller__Unauthorized.selector);
        lendtroller.listToken(address(dUSDC));
    }

    function test_listToken_fail_whenMTokenIsAlreadyListed() public {
        lendtroller.listToken(address(dUSDC));

        vm.expectRevert(Lendtroller.Lendtroller__TokenAlreadyListed.selector);
        lendtroller.listToken(address(dUSDC));
    }

    function test_listToken_fail_whenMTokenIsInvalid() public {
        vm.expectRevert();
        lendtroller.listToken(address(1));
    }

    function test_listToken_success() public {
        (bool isListed, , uint256 collateralizationRatio) = lendtroller
            .getMTokenData(address(dUSDC));
        assertFalse(isListed);
        assertEq(collateralizationRatio, 0);

        vm.expectEmit(true, true, true, true, address(lendtroller));
        emit MarketListed(address(dUSDC));

        lendtroller.listToken(address(dUSDC));

        (isListed, , collateralizationRatio) = lendtroller.getMTokenData(
            address(dUSDC)
        );
        assertTrue(isListed);
        assertEq(collateralizationRatio, 0);

        assertEq(dUSDC.totalSupply(), 42069);
    }
}
