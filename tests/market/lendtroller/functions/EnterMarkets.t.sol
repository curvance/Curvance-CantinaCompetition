// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseLendtroller } from "../TestBaseLendtroller.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";

contract EnterMarketsTest is TestBaseLendtroller {
    address[] public tokens;

    event MarketEntered(address mToken, address account);

    function setUp() public override {
        super.setUp();

        tokens.push(address(dUSDC));
        tokens.push(address(dDAI));
        tokens.push(address(cBALRETH));
    }

    function test_enterMarkets_fail_whenParameterIsInvalid() public {
        vm.expectRevert(Lendtroller.Lendtroller__InvalidParameter.selector);
        lendtroller.enterMarkets(new address[](0));
    }

    function test_enterMarkets_success_whenMarketIsNotListed() public {
        for (uint256 i = 0; i < tokens.length; i++) {
            (bool isListed, , uint256 collateralizationRatio) = lendtroller
                .getMTokenData(tokens[i]);
            assertFalse(isListed);
            assertEq(collateralizationRatio, 0);
            assertFalse(
                lendtroller.getAccountMembership(tokens[i], address(this))
            );
        }

        lendtroller.enterMarkets(tokens);

        for (uint256 i = 0; i < tokens.length; i++) {
            (bool isListed, , uint256 collateralizationRatio) = lendtroller
                .getMTokenData(tokens[i]);
            assertFalse(isListed);
            assertEq(collateralizationRatio, 0);
            assertFalse(
                lendtroller.getAccountMembership(tokens[i], address(this))
            );
        }
    }

    function test_enterMarkets_success_whenUserAlreadyJoinedMarket() public {
        for (uint256 i = 0; i < tokens.length; i++) {
            lendtroller.listToken(tokens[i]);
        }

        lendtroller.enterMarkets(tokens);

        for (uint256 i = 0; i < tokens.length; i++) {
            (bool isListed, , uint256 collateralizationRatio) = lendtroller
                .getMTokenData(tokens[i]);
            assertTrue(isListed);
            assertEq(collateralizationRatio, 0);
            assertTrue(
                lendtroller.getAccountMembership(tokens[i], address(this))
            );
        }

        lendtroller.enterMarkets(tokens);

        for (uint256 i = 0; i < tokens.length; i++) {
            (bool isListed, , uint256 collateralizationRatio) = lendtroller
                .getMTokenData(tokens[i]);
            assertTrue(isListed);
            assertEq(collateralizationRatio, 0);
            assertTrue(
                lendtroller.getAccountMembership(tokens[i], address(this))
            );
        }
    }

    function test_enterMarkets_success() public {
        for (uint256 i = 0; i < tokens.length; i++) {
            lendtroller.listToken(tokens[i]);
        }

        for (uint256 i = 0; i < tokens.length; i++) {
            (bool isListed, , uint256 collateralizationRatio) = lendtroller
                .getMTokenData(tokens[i]);
            assertTrue(isListed);
            assertEq(collateralizationRatio, 0);
            assertFalse(
                lendtroller.getAccountMembership(tokens[i], address(this))
            );

            vm.expectEmit(true, true, true, true, address(lendtroller));
            emit MarketEntered(tokens[i], address(this));
        }

        lendtroller.enterMarkets(tokens);

        for (uint256 i = 0; i < tokens.length; i++) {
            (bool isListed, , uint256 collateralizationRatio) = lendtroller
                .getMTokenData(tokens[i]);
            assertTrue(isListed);
            assertEq(collateralizationRatio, 0);
            assertTrue(
                lendtroller.getAccountMembership(tokens[i], address(this))
            );
        }
    }
}
