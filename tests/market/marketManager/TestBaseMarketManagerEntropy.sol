// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./TestBaseMarketManagerMultiMarkets.sol";

contract TestBaseMarketManagerEntropy is TestBaseMarketManagerMultiMarkets {
    uint256 public entropy;

    function _genRandom(uint256 _value, uint256 _entropy, uint256 _lower, uint256 _upper)
        internal
        pure
        returns (uint256)
    {
        return _lower == _upper
            ? _lower
            : (uint256(keccak256(abi.encodePacked(_value, _entropy))) % (_upper - _lower)) + _lower;
    }

    function _genCollateralateraltoken(uint256 _noOfTokens, uint256 _entropy)
        internal
        returns (MockCToken[] memory, MockV3Aggregator[] memory, MockV3Aggregator[] memory)
    {
        MockCToken[] memory cTokens = new MockCToken[](_noOfTokens);
        MockV3Aggregator[] memory cTokensAgg = new MockV3Aggregator[](_noOfTokens);
        MockV3Aggregator[] memory cTokensUnderlyingAgg = new MockV3Aggregator[](_noOfTokens);
        for (uint256 i = 0; i < _noOfTokens; i++) {
            MockCToken cToken = _deployCollaterToken();
            cTokens[i] = cToken;
            cTokensAgg[i] = _deployPriceRouterForToken(cToken.underlying());
            cTokensUnderlyingAgg[i] = _deployPriceRouterForToken(address(cToken));
            if (_entropy > 0) {
                console2.log("a %s", i);
                _setCollateralDataWithEntropy(address(cToken), i, _entropy + i);
            } else {
                _setCollateralData(address(cToken));
            }
            console2.log("b %s", i);
            _setCollateralData(address(cToken));
        }
        return (cTokens, cTokensAgg, cTokensUnderlyingAgg);
    }

    function _setCollateralDataWithEntropy(address collateralToken, uint256 index, uint256 entropy) internal {
        // set collateral factor
        uint256 collRatio = _genRandom(entropy, index, 3000, 9100);
        uint256 collReqA = _genRandom(entropy, index + 1, 1000, 4000);
        console2.log("collRatio %s collReqA %s", collRatio, collReqA);
        uint256 collReqALimit = (1e4 * 1e4) / collRatio - 1e4;
        console2.log("collReqALimit %s", collReqALimit);
        if (collReqA > collReqALimit) {
            collReqA = collReqALimit;
        }
        colRatios[index] = collRatio;

        uint256 collReqB = _genRandom(entropy, index + 2, collReqA / 2, collReqA) - (collReqA / 4);
        if (collReqB <= 400 + (marketManager.MIN_EXCESS_COLLATERAL_REQUIREMENT() / 10 ** 14)) {
            collReqB = 400 + (marketManager.MIN_EXCESS_COLLATERAL_REQUIREMENT() / 10 ** 14) + 1;
        }

        marketManager.updateCollateralToken(IMToken(collateralToken), collRatio, collReqA, collReqB, 200, 400, 10, 1000);
        address[] memory tokens = new address[](1);
        tokens[0] = address(collateralToken);
        uint256[] memory caps = new uint256[](1);
        caps[0] = 100_000e18;
        marketManager.setCTokenCollateralCaps(tokens, caps);
    }

    function _genColWithEntropy(address user, MockCToken cToken, uint256 amount) internal {
        _genCollateral(user, cToken, amount);
        _postCollateral(user, cToken, amount);
    }

    function _supplyDTokenWithEntropy(address user, DToken dToken, uint256 amount) internal {
        _supplyDToken(user, dToken, amount);
    }

    function _selectBorrow(uint256 i, DToken[] memory dTokens, uint256 noOfDebtTokens)
        internal
        view
        returns (bool, DToken, uint256)
    {
        console2.log("select borrow");
        DToken borrowToken = dTokens[_genRandom(i, entropy, 0, noOfDebtTokens)];
        uint256 amount = borrowToken.marketUnderlyingHeld();
        console2.log("amount %s", amount);
        if (amount < uint256(borrowToken.decimals()) * 100) {
            for (uint256 j = 0; j < noOfDebtTokens; j++) {
                if (dTokens[j].marketUnderlyingHeld() > uint256(dTokens[j].decimals()) * 100) {
                    borrowToken = dTokens[j];
                    amount = dTokens[j].marketUnderlyingHeld();
                    return (false, borrowToken, amount);
                }
            }
            return (true, borrowToken, amount);
        }
        return (false, borrowToken, amount);
    }

    function _executeBorrows(address[] memory users, DToken[] memory dTokens, MockCToken[] memory colToken) internal {
        uint256 amount;
        uint256 borrowToken;

        for (uint256 i = 0; i < noOfCollateralTokens; i++) {
            console2.log("col token %s col ratio %s", i, colRatios[i]);
        }

        console2.log("borrow");

        for (uint256 i = 0; i < noOfUsersCollateral; i++) {
            console2.log("user %s", i);
            while (true) {
                (solvency, debt) = marketManager.solvencyOf(users[i]);
                (accCollateral, accMaxDebt, accDebt) = marketManager.statusOf(users[i]);
                amount = _genRandom(i, entropy, 0.2 ether, 1 ether);
                console2.log("borrow amount %s", amount);
                console2.log("solvency %s debt %s", solvency, debt);
                console2.log("status col %s max debt %s debt %s", accCollateral, accMaxDebt, accDebt);
                (, DToken borrowToken, uint256 avail) = _selectBorrow(i, dTokens, noOfDebtTokens);

                console2.log("avail %s amount %s", avail, amount);
                if (avail < amount) {
                    amount = avail / 2;
                }

                console2.log("borrowToken %s", address(borrowToken));
                if (accMaxDebt - accDebt < amount) {
                    _borrow(users[i], borrowToken, ((accMaxDebt - accDebt) * 9500) / 10000);
                    break;
                } else {
                    _borrow(users[i], borrowToken, amount);
                }
            }
        }
    }

    function _updateRoundDataWithEntropy(MockV3Aggregator _agg, uint256 i) internal {
        uint256 _price = _genRandom(i, entropy, 1e7, 2e7);
        _agg.updateRoundData(uint80(_agg.latestRound() + 1), int256(_price), block.timestamp, block.timestamp);
    }
}
