// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseLendtroller } from "../TestBaseLendtroller.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";
import { IMToken } from "contracts/interfaces/market/IMToken.sol";

contract ExitMarketTest is TestBaseLendtroller {
    address[] public tokens;

    event MarketExited(address mToken, address account);

    function setUp() public override {
        super.setUp();

        tokens.push(address(dUSDC));
        tokens.push(address(dDAI));
        tokens.push(address(cBALRETH));

        for (uint256 i = 0; i < tokens.length; i++) {
            lendtroller.listToken(tokens[i]);
        }
    }

    // function test_exitMarket_fail_whenAmountOwedIsNotZero() public {
    //     dUSDC.borrow(1);

    //     vm.expectRevert(Lendtroller.Lendtroller__HasActiveLoan.selector);
    //     lendtroller.exitMarket(address(dUSDC));
    // }

    // function test_exitMarket_success_whenUserNotJoinedMarket() public {
    //     for (uint256 i = 0; i < tokens.length; i++) {
    //         (bool isListed, , uint256 collateralizationRatio) = lendtroller
    //             .getMTokenData(tokens[i]);
    //         assertTrue(isListed);
    //         assertEq(collateralizationRatio, 0);
    //         assertFalse(
    //             lendtroller.getAccountMembership(tokens[i], address(this))
    //         );

    //         lendtroller.exitMarket(tokens[i]);

    //         (isListed, , collateralizationRatio) = lendtroller.getMTokenData(
    //             tokens[i]
    //         );
    //         assertTrue(isListed);
    //         assertEq(collateralizationRatio, 0);
    //         assertFalse(
    //             lendtroller.getAccountMembership(tokens[i], address(this))
    //         );
    //     }
    // }

    // function test_exitMarket_success() public {
    //     lendtroller.enterMarkets(tokens);

    //     for (uint256 i = 0; i < tokens.length; i++) {
    //         IMToken[] memory assets = lendtroller.getAccountAssets(
    //             address(this)
    //         );
    //         uint256 assetIndex;
    //         for (; assetIndex < assets.length; assetIndex++) {
    //             if (tokens[i] == address(assets[assetIndex])) {
    //                 break;
    //             }
    //         }

    //         assertNotEq(assetIndex, assets.length);
    //         assertEq(tokens[i], address(assets[assetIndex]));

    //         (bool isListed, uint256 collateralizationRatio) = lendtroller
    //             .getMTokenData(tokens[i]);
    //         assertTrue(isListed);
    //         assertEq(collateralizationRatio, 0);
    //         assertTrue(
    //             lendtroller.getAccountMembership(tokens[i], address(this))
    //         );

    //         vm.expectEmit(true, true, true, true, address(lendtroller));
    //         emit MarketExited(tokens[i], address(this));

    //         lendtroller.exitMarket(tokens[i]);

    //         assets = lendtroller.getAccountAssets(address(this));

    //         assetIndex = 0;
    //         for (; assetIndex < assets.length; assetIndex++) {
    //             if (tokens[i] == address(assets[assetIndex])) {
    //                 break;
    //             }
    //         }

    //         assertEq(assetIndex, assets.length);

    //         (isListed, collateralizationRatio) = lendtroller
    //             .getMTokenData(tokens[i]);
    //         assertTrue(isListed);
    //         assertEq(collateralizationRatio, 0);
    //         assertFalse(
    //             lendtroller.getAccountMembership(tokens[i], address(this))
    //         );
    //     }
    // }
}
