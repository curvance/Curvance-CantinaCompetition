// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../TestBaseMarketManagerEntropy.sol";
import { MockCTokenPrimitive } from "contracts/mocks/MockCTokenPrimitive.sol";

import { WAD } from "contracts/libraries/Constants.sol";
import { PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";

//import "tests/market/TestBaseMarket.sol";

//import "./MockERC20Token.sol";
import "forge-std/console2.sol";

contract TestMarketManager is TestBaseMarketManagerEntropy {
    function setUp() public override {
        _deployCentralRegistry();
        _deployCVE();
        _deployCVELocker();
        _deployVeCVE();
        _deployGaugePool();
        _deployMarketManager();
        _deployDynamicInterestRateModel();
        // eth/usd is needed in price router constructor
        chainlinkEthUsd = new MockV3Aggregator(8, 1500e8, 1e50, 1e6);
        _deployOracleRouter();
        chainlinkAdaptor = new ChainlinkAdaptor(
            ICentralRegistry(address(centralRegistry))
        );
        oracleRouter.addApprovedAdaptor(address(chainlinkAdaptor));
        // start gauge to enable deposits
        gaugePool.start(address(marketManager));
        vm.warp(veCVE.nextEpochStartTime() + 1000);
        chainlinkEthUsd.updateAnswer(1500e8);
    }

    function testHypotheticalLiquidityOf() public {
        address[] memory users = new address[](3);
        users[0] = address(0x1111);
        users[1] = address(0x2222);
        users[2] = address(0x3333);

        noOfCollateralTokens = 2;
        noOfDebtTokens = 2;

        MockCTokenPrimitive[] memory cTokens = new MockCTokenPrimitive[](
            noOfCollateralTokens
        );
        DToken[] memory dTokens = new DToken[](noOfDebtTokens);
        MockV3Aggregator[] memory cTokensAgg = new MockV3Aggregator[](
            noOfCollateralTokens
        );
        MockV3Aggregator[]
            memory cTokensUnderlyingAgg = new MockV3Aggregator[](
                noOfCollateralTokens
            );
        MockV3Aggregator[] memory dTokensAgg = new MockV3Aggregator[](
            noOfDebtTokens
        );

        (
            cTokens,
            cTokensAgg,
            cTokensUnderlyingAgg
        ) = _genCollateralateraltoken(noOfCollateralTokens, 0);
        (dTokens, dTokensAgg) = _genDebtToken(noOfDebtTokens);

        _genCollateral(users[0], cTokens[0], 1 ether);
        _postCollateral(users[0], cTokens[0], 1 ether);

        _genCollateral(users[1], cTokens[1], 1 ether);
        _postCollateral(users[1], cTokens[1], 1 ether);

        _genCollateral(users[2], cTokens[1], 1 ether);
        _postCollateral(users[2], cTokens[1], 1 ether);

        _supplyDToken(users[2], dTokens[0], 3 ether);

        _borrow(users[0], dTokens[0], 0.7 ether);
        _borrow(users[1], dTokens[0], 0.7 ether);
        _borrow(users[2], dTokens[0], 0.7 ether);

        for (uint256 i = 0; i < noOfCollateralTokens; i++) {
            skip(20 minutes);
            _updateRoundData(cTokensAgg[i], 0, 1e7);
        }

        vm.expectRevert(
            MarketManager.MarketManager__InvalidParameter.selector
        );
        marketManager.hypotheticalLiquidityOf(
            users[0],
            address(cTokens[0]),
            0,
            1
        );

        (uint256 liquidity, uint256 debt) = marketManager
            .hypotheticalLiquidityOf(users[0], address(cTokens[0]), 0, 0);

        assertEq(liquidity, 0);
        assertGt(debt, 0);
    }

    // function testClosePosition() public {
    //     address[] memory users = new address[](3);
    //     users[0] = address(0x1111);
    //     users[1] = address(0x2222);
    //     users[2] = address(0x3333);

    //     noOfCollateralTokens = 2;
    //     noOfDebtTokens = 2;

    //     MockCTokenPrimitive[] memory cTokens = new MockCTokenPrimitive[](
    //         noOfCollateralTokens
    //     );
    //     DToken[] memory dTokens = new DToken[](noOfDebtTokens);
    //     MockV3Aggregator[] memory cTokensAgg = new MockV3Aggregator[](
    //         noOfCollateralTokens
    //     );
    //     MockV3Aggregator[]
    //         memory cTokensUnderlyingAgg = new MockV3Aggregator[](
    //             noOfCollateralTokens
    //         );
    //     MockV3Aggregator[] memory dTokensAgg = new MockV3Aggregator[](
    //         noOfDebtTokens
    //     );

    //     (
    //         cTokens,
    //         cTokensAgg,
    //         cTokensUnderlyingAgg
    //     ) = _genCollateralateraltoken(noOfCollateralTokens, 0);
    //     (dTokens, dTokensAgg) = _genDebtToken(noOfDebtTokens);

    //     _genCollateral(users[0], cTokens[0], 1 ether);
    //     _postCollateral(users[0], cTokens[0], 1 ether);

    //     _genCollateral(users[1], cTokens[1], 1 ether);
    //     _postCollateral(users[1], cTokens[1], 1 ether);

    //     _genCollateral(users[2], cTokens[1], 1 ether);
    //     _postCollateral(users[2], cTokens[1], 1 ether);

    //     _supplyDToken(users[2], dTokens[0], 3 ether);

    //     _borrow(users[0], dTokens[0], 0.7 ether);
    //     _borrow(users[1], dTokens[0], 0.7 ether);
    //     _borrow(users[2], dTokens[0], 0.7 ether);

    //     vm.startPrank(users[0]);
    //     vm.expectRevert(MarketManager.MarketManager__Unauthorized.selector);
    //     marketManager.closePosition(address(dTokens[0]));
    //     vm.stopPrank();

    //     skip(30 minutes);
    //     _repay(
    //         users[0],
    //         dTokens[0],
    //         dTokens[0].balanceOfUnderlyingSafe(users[0])
    //     );
    //     vm.startPrank(users[0]);
    //     marketManager.closePosition(address(dTokens[0]));
    //     vm.stopPrank();

    //     vm.startPrank(users[0]);
    //     vm.expectRevert(
    //         MarketManager.MarketManager__InvalidParameter.selector
    //     );
    //     marketManager.closePosition(address(dTokens[1]));
    //     vm.stopPrank();

    //     vm.startPrank(users[0]);
    //     marketManager.closePosition(address(cTokens[0]));
    //     vm.stopPrank();

    //     vm.startPrank(users[0]);
    //     marketManager.closePosition(address(cTokens[0]));
    //     vm.stopPrank();
    // }
}
