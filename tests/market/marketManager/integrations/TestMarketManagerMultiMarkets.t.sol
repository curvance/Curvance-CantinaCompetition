// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../TestBaseMarketManagerEntropy.sol";
import { MockCTokenPrimitive } from "contracts/mocks/MockCTokenPrimitive.sol";

import { WAD } from "contracts/libraries/Constants.sol";
import { PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";

//import "tests/market/TestBaseMarket.sol";

//import "./MockERC20Token.sol";
import "forge-std/console2.sol";

contract TestMarketManagerMultiMarkets is TestBaseMarketManagerEntropy {
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
        chainlinkAdaptor = new ChainlinkAdaptor(ICentralRegistry(address(centralRegistry)));
        oracleRouter.addApprovedAdaptor(address(chainlinkAdaptor));
        // start gauge to enable deposits
        gaugePool.start(address(marketManager));
        vm.warp(veCVE.nextEpochStartTime() + 1000);
    }

    function setUpFuzzTest(uint16 _noOfCollateralTokens, uint16 _noOfDebtTokens, uint16 _noOfUsers, uint16 _entropy)
        internal
        returns (
            MockCTokenPrimitive[] memory,
            DToken[] memory,
            address[] memory,
            MockV3Aggregator[] memory,
            MockV3Aggregator[] memory,
            MockV3Aggregator[] memory
        )
    {
        noOfCollateralTokens = uint256((_noOfCollateralTokens % 5)) + 2;
        noOfDebtTokens = uint256((_noOfDebtTokens % 5)) + 1;
        noOfUsersCollateral = uint256((_noOfUsers % 3)) + 2;
        noOfUsersDebt = uint256((_noOfUsers % 3)) + 1;
        noOfUsersMixed = uint256((_noOfUsers % 2)) + 1;
        noOfUsers = noOfUsersCollateral + noOfUsersDebt + noOfUsersMixed;
        entropy = uint256(_entropy) + 1;

        MockCTokenPrimitive[] memory cTokens = new MockCTokenPrimitive[](noOfCollateralTokens);
        DToken[] memory dTokens = new DToken[](noOfDebtTokens);
        address[] memory users = new address[](noOfUsers);

        MockV3Aggregator[] memory cTokensAgg = new MockV3Aggregator[](noOfCollateralTokens);
        MockV3Aggregator[] memory cTokensUnderlyingAgg = new MockV3Aggregator[](noOfCollateralTokens);
        MockV3Aggregator[] memory dTokensAgg = new MockV3Aggregator[](noOfDebtTokens);

        for (uint256 i = 0; i < noOfUsers; i++) {
            users[i] = address(uint160((i + 100)));
        }
        (cTokens, cTokensAgg, cTokensUnderlyingAgg) = _genCollateralateraltoken(noOfCollateralTokens, entropy);

        (dTokens, dTokensAgg) = _genDebtToken(noOfDebtTokens);
        return (cTokens, dTokens, users, cTokensAgg, cTokensUnderlyingAgg, dTokensAgg);
    }

    function _setupLiquidity(
        uint256 collateralLimit,
        uint256 debtLimit,
        address[] memory users,
        MockCTokenPrimitive[] memory cTokens,
        DToken[] memory dTokens
    ) internal {
        uint256 runs;
        uint256 _amountCollateral;
        uint256 _amountDebt;
        for (uint256 i = 0; i < noOfUsers; i++) {
            runs = _genRandom(i, entropy, 1, noOfCollateralTokens);
            for (uint256 j = 0; j < runs; j++) {
                console2.log("collateralLimt %s", collateralLimit);
                console2.log("debtLimit %s", debtLimit);
                _amountCollateral = _genRandom(i, entropy, 1 ether, collateralLimit);
                _amountDebt = _genRandom(i, entropy, 1 ether, debtLimit);
                if (i < noOfUsersCollateral) {
                    _genColWithEntropy(users[i], cTokens[j], _amountCollateral);
                } else if (i < noOfUsersCollateral + noOfUsersDebt) {
                    _supplyDTokenWithEntropy(users[i], dTokens[j % noOfDebtTokens], _amountDebt);
                } else {
                    _genColWithEntropy(users[i], cTokens[j], _amountCollateral);
                    _supplyDTokenWithEntropy(users[i], dTokens[j % noOfDebtTokens], _amountDebt);
                }
            }
        }
        _executeBorrows(users, dTokens, cTokens);
    }

    function testLiquidationMultipleMarkets() public {
        address[] memory users = new address[](3);
        users[0] = address(0x1111);
        users[1] = address(0x2222);
        users[2] = address(0x3333);

        noOfCollateralTokens = 2;
        noOfDebtTokens = 2;

        MockCTokenPrimitive[] memory cTokens = new MockCTokenPrimitive[](noOfCollateralTokens);
        DToken[] memory dTokens = new DToken[](noOfDebtTokens);
        MockV3Aggregator[] memory cTokensAgg = new MockV3Aggregator[](noOfCollateralTokens);
        MockV3Aggregator[] memory cTokensUnderlyingAgg = new MockV3Aggregator[](noOfCollateralTokens);
        MockV3Aggregator[] memory dTokensAgg = new MockV3Aggregator[](noOfDebtTokens);

        (cTokens, cTokensAgg, cTokensUnderlyingAgg) = _genCollateralateraltoken(noOfCollateralTokens, 0);
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

        _liquidate(dTokens[0], cTokens[0], users[0], false);
        _liquidate(dTokens[0], cTokens[1], users[1], true);

        _prepareLiquidationMultiple(liquidator, dTokens);
        _liquidateAccount(users[2], liquidator);
    }

    function testLiquidationMultipleMarketsWithEntropyDtoken(
        uint16 _noOfCollateralTokens,
        uint16 _noOfDebtTokens,
        uint16 _noOfUsers,
        uint16 _entropy
    ) public {
        (
            MockCTokenPrimitive[] memory cTokens,
            DToken[] memory dTokens,
            address[] memory users,
            MockV3Aggregator[] memory cTokensAgg,
            MockV3Aggregator[] memory cTokensUnderlyingAgg,
            MockV3Aggregator[] memory dTokensAgg
        ) = setUpFuzzTest(_noOfCollateralTokens, _noOfDebtTokens, _noOfUsers, _entropy);
        _setupLiquidity(1 ether, 2 ether, users, cTokens, dTokens);

        for (uint256 i; i < noOfCollateralTokens; i++) {
            skip(20 minutes);
            _updateRoundData(cTokensAgg[0], 0, 1e7);
        }

        _liquidateAllByDToken(dTokens, cTokens, users);
    }

    function testLiquidationMultipleMarketsWithEntropyExact(
        uint16 _noOfCollateralTokens,
        uint16 _noOfDebtTokens,
        uint16 _noOfUsers,
        uint16 _entropy
    ) public {
        (
            MockCTokenPrimitive[] memory cTokens,
            DToken[] memory dTokens,
            address[] memory users,
            MockV3Aggregator[] memory cTokensAgg,
            MockV3Aggregator[] memory cTokensUnderlyingAgg,
            MockV3Aggregator[] memory dTokensAgg
        ) = setUpFuzzTest(_noOfCollateralTokens, _noOfDebtTokens, _noOfUsers, _entropy);
        _setupLiquidity(1 ether, 2 ether, users, cTokens, dTokens);

        for (uint256 i; i < noOfCollateralTokens; i++) {
            skip(20 minutes);
            _updateRoundData(cTokensAgg[0], 0, 1e7);
        }

        _liquidateAllExact(dTokens, cTokens, users);
    }

    function testLiquidationMultipleMarketsWithEntropyAccount(
        uint16 _noOfCollateralTokens,
        uint16 _noOfDebtTokens,
        uint16 _noOfUsers,
        uint16 _entropy
    ) public {
        (
            MockCTokenPrimitive[] memory cTokens,
            DToken[] memory dTokens,
            address[] memory users,
            MockV3Aggregator[] memory cTokensAgg,
            MockV3Aggregator[] memory cTokensUnderlyingAgg,
            MockV3Aggregator[] memory dTokensAgg
        ) = setUpFuzzTest(_noOfCollateralTokens, _noOfDebtTokens, _noOfUsers, _entropy);
        _setupLiquidity(1 ether, 2 ether, users, cTokens, dTokens);

        for (uint256 i; i < noOfCollateralTokens; i++) {
            skip(20 minutes);
            _updateRoundData(cTokensAgg[0], 0, 1e7);
        }

        _prepareLiquidationMultiple(liquidator, dTokens);
        for (uint256 i = 0; i < noOfUsersCollateral; i++) {
            if (!marketManager.flaggedForLiquidation(users[i])) {
                continue;
            }
            _liquidateAccount(users[i], liquidator);
        }
    }

    function _compareUserAssets(
        IMToken[] memory userAssets,
        uint256[] memory cTokenBalancesPre,
        uint256[] memory dTokenBalancesPre,
        uint256[] memory underlyingBalancesPre,
        address user
    ) internal {
        uint256[] memory cTokenBalances = new uint256[](noOfCollateralTokens);
        uint256[] memory dTokenBalances = new uint256[](noOfDebtTokens);
        uint256[] memory underlyingBalances = new uint256[](noOfDebtTokens);

        for (uint256 i = 0; i < userAssets.length; i++) {
            if (userAssets[i].isCToken()) {
                cTokenBalances[i] = userAssets[i].balanceOf(user);
            } else {
                dTokenBalances[i] = userAssets[i].balanceOf(user);
                underlyingBalances[i] = IERC20(userAssets[i].underlying()).balanceOf(user);
            }
        }
        console2.log("\nuser %s", user);
        console2.log("\ncTokenBalances");
        for (uint256 i = 0; i < noOfCollateralTokens; i++) {
            console2.log("pre %s post %s", cTokenBalancesPre[i], cTokenBalances[i]);
        }
        console2.log("\ndTokenBalances");
        for (uint256 i = 0; i < noOfDebtTokens; i++) {
            console2.log("pre %s post %s", dTokenBalancesPre[i], dTokenBalances[i]);
        }
        console2.log("\nunderlyingBalances");
        for (uint256 i = 0; i < noOfDebtTokens; i++) {
            console2.log("pre %s post %s", underlyingBalancesPre[i], underlyingBalances[i]);
        }
    }
}
