// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "tests/market/TestBaseMarket.sol";
import { MockCTokenPrimitive } from "contracts/mocks/MockCTokenPrimitive.sol";
import { MockERC20Token } from "contracts/mocks/MockERC20Token.sol";

import { WAD } from "contracts/libraries/Constants.sol";
import { PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";

import "forge-std/console2.sol";

contract TestBaseMarketManagerMultiMarkets is TestBaseMarket {
    uint256 constant MAX_DEPOSIT = 1e26;
    uint256 constant MIN_WITHDRAW = 1e18;
    uint256 constant BP = 1e4;
    uint256 constant MAX_TOKENS = 10;
    uint256 constant MAX_USERS = 20;

    uint256 noOfCollateralTokens;
    uint256 noOfDebtTokens;
    uint256 noOfUsersCollateral;

    uint256 noOfUsersDebt;
    uint256 noOfUsersMixed;
    uint256 noOfUsers;

    uint256 solvency;
    uint256 debt;

    uint256 accCollateral;
    uint256 accMaxDebt;
    uint256 accDebt;

    uint256[MAX_TOKENS] colRatios;

    function _genDebtToken(
        uint256 _noOfTokens
    ) internal returns (DToken[] memory, MockV3Aggregator[] memory) {
        DToken[] memory dTokens = new DToken[](_noOfTokens);
        MockV3Aggregator[] memory dTokensAgg = new MockV3Aggregator[](
            _noOfTokens
        );
        for (uint256 i = 0; i < _noOfTokens; i++) {
            DToken dToken = _deployDebtToken();
            dTokens[i] = dToken;
            dTokensAgg[i] = _deployOracleRouterForToken(dToken.underlying());
        }
        return (dTokens, dTokensAgg);
    }

    function _deployCollaterToken() internal returns (MockCTokenPrimitive) {
        // deploy collateral token and cToken
        MockERC20Token mockUnderlying = new MockERC20Token();
        vm.label(address(mockUnderlying), "tokenCollateral");
        MockCTokenPrimitive cTokenPrimitive = new MockCTokenPrimitive(
            ICentralRegistry(address(centralRegistry)),
            address(mockUnderlying),
            address(marketManager)
        );
        vm.label(address(cTokenPrimitive), "cToken");

        // start market for cToken
        uint256 startAmount = 42069;
        mockUnderlying.mint(address(this), startAmount);
        mockUnderlying.approve(address(cTokenPrimitive), startAmount);
        marketManager.listToken(address(cTokenPrimitive));
        vm.label(address(marketManager), "marketManager");
        return cTokenPrimitive;
    }

    function _deployDebtToken() internal returns (DToken) {
        // start market for dToken
        MockERC20Token mockUnderlying = new MockERC20Token();
        vm.label(address(mockUnderlying), "tokenDebt");
        DToken debtToken = _deployDToken(address(mockUnderlying));
        vm.label(address(debtToken), "dToken");
        uint256 startAmount = 42069;
        mockUnderlying.mint(address(this), startAmount);
        mockUnderlying.approve(address(debtToken), startAmount);
        marketManager.listToken(address(debtToken));
        return debtToken;
    }

    function _deployOracleRouterForToken(
        address token
    ) internal returns (MockV3Aggregator) {
        MockV3Aggregator oneUsd = new MockV3Aggregator(8, 1e8, 1e10, 1e5);
        chainlinkAdaptor.addAsset(token, address(oneUsd), 0, true);
        oracleRouter.addAssetPriceFeed(token, address(chainlinkAdaptor));
        return oneUsd;
    }

    function _setCollateralData(address collateralToken) internal {
        // set collateral factor
        marketManager.updateCollateralToken(
            IMToken(collateralToken),
            7000,
            4000,
            3000,
            200,
            400,
            10,
            1000
        );
        address[] memory tokens = new address[](1);
        tokens[0] = address(collateralToken);
        uint256[] memory caps = new uint256[](1);
        caps[0] = 100_000e18;
        marketManager.setCTokenCollateralCaps(tokens, caps);
    }

    function _genCollateral(
        address _user,
        MockCTokenPrimitive _cToken,
        uint256 _amount
    ) internal {
        MockERC20Token tokenCollateral = MockERC20Token(_cToken.underlying());
        vm.startPrank(_user);
        tokenCollateral.mint(address(_user), _amount);
        tokenCollateral.approve(address(_cToken), _amount);
        _cToken.deposit(_amount, address(_user));
        vm.stopPrank();
    }

    function _postCollateral(
        address _user,
        MockCTokenPrimitive _cToken,
        uint256 _amount
    ) internal {
        vm.prank(_user);
        marketManager.postCollateral(
            address(_user),
            address(_cToken),
            _amount
        );
    }

    function _withdraw(
        address _user,
        MockCTokenPrimitive _cToken,
        uint256 _amount
    ) internal {
        vm.prank(_user);
        _cToken.withdraw(1e20, address(_user), address(_user));
    }

    function _supplyDToken(
        address _user,
        DToken _dToken,
        uint256 _amount
    ) internal {
        MockERC20Token tokenDebt = MockERC20Token(_dToken.underlying());
        vm.startPrank(_user);
        tokenDebt.mint(address(_user), _amount);
        tokenDebt.approve(address(_dToken), _amount);
        _dToken.mint(_amount);
        vm.stopPrank();
    }

    function _borrow(address _user, DToken _dToken, uint256 _amount) internal {
        vm.startPrank(_user);
        _dToken.borrow(_amount);
        vm.stopPrank();
    }

    function _repay(address _user, DToken _dToken, uint256 _amount) internal {
        MockERC20Token tokenDebt = MockERC20Token(_dToken.underlying());
        vm.startPrank(_user);
        tokenDebt.approve(address(_dToken), _amount);
        _dToken.repay(_amount);
        vm.stopPrank();
    }

    function _checkLiquidation(
        address _user,
        DToken _dToken,
        MockCTokenPrimitive _cToken,
        uint256 _amount,
        bool _exact
    )
        internal view
        returns (
            uint256 liqAmount,
            uint256 liquidatedTokens,
            uint256 protocolTokens
        )
    {
        (liqAmount, liquidatedTokens, protocolTokens) = marketManager
            .canLiquidate(
                address(_dToken),
                address(_cToken),
                _user,
                _amount,
                _exact
            );

        console2.log(
            "liqAmount %s liquidatedTokens %s protocolTokens %s",
            liqAmount,
            liquidatedTokens,
            protocolTokens
        );
    }

    function _prepareLiquidation(
        address _liquidator,
        DToken _dToken,
        uint256 _amount
    ) internal {
        vm.startPrank(_liquidator);
        console2.log("\n prep liq");
        MockERC20Token tokenDebt = MockERC20Token(_dToken.underlying());
        console2.log(
            "dtoken %s underlying %s",
            address(_dToken),
            address(tokenDebt)
        );
        console2.log("liquidator %s", liquidator);
        tokenDebt.approve(address(_dToken), _amount);
        tokenDebt.mint(_liquidator, _amount); // this doesnt seem to alignt when a user is affected accross multiple markets
        vm.stopPrank();
    }

    function _prepareLiquidationMultiple(
        address _liquidator,
        DToken[] memory _dTokens
    ) internal {
        vm.startPrank(_liquidator);
        for (uint256 i = 0; i < _dTokens.length; i++) {
            MockERC20Token tokenDebt = MockERC20Token(
                _dTokens[i].underlying()
            );
            tokenDebt.approve(address(_dTokens[i]), 1e26);
            tokenDebt.mint(_liquidator, 1e26);
        }
        vm.stopPrank();
    }

    function _expectedLiquidation(
        uint256 _collateralAvailable,
        address _user,
        DToken _dToken,
        MockCTokenPrimitive _cToken
    ) internal view returns (uint256, uint256, uint256) {
        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            uint256 baseCFactor,
            uint256 cFactorCurve
        ) = marketManager.tokenData(address(_cToken));

        uint256 cFactor = baseCFactor + ((cFactorCurve * 1e18) / WAD);
        uint256 debtAmount = (cFactor * _dToken.debtBalanceCached(_user)) /
            WAD;

        PriceReturnData memory data = chainlinkAdaptor.getPrice(
            _cToken.underlying(),
            true,
            true
        );
        return
            _calcExpected(
                _collateralAvailable,
                _dToken,
                _cToken,
                cFactor,
                debtAmount,
                data.price
            );
    }

    function _calcExpected(
        uint256 _collateralAvailable,
        DToken _dToken,
        MockCTokenPrimitive _cToken,
        uint256 cFactor,
        uint256 debtAmount,
        uint256 price
    )
        internal
        view
        returns (
            uint256 expectedLiqAmount,
            uint256 collateralAvailable,
            uint256 expectedProtocolTokens
        )
    {
        collateralAvailable = _collateralAvailable - 1;
        (
            ,
            ,
            ,
            ,
            uint256 liqBaseIncentive,
            uint256 liqCurve,
            ,
            ,

        ) = marketManager.tokenData(address(_cToken));

        PriceReturnData memory debtTokenData = chainlinkAdaptor.getPrice(
            _dToken.underlying(),
            true,
            true
        );
        uint256 debtTokenPrice = uint256(debtTokenData.price);
        console2.log("debtTokenPrice %s", debtTokenPrice);
        console2.log("incentive %s %s", liqBaseIncentive, liqCurve);

        uint256 incentive = liqBaseIncentive + liqCurve;
        uint256 debtToCollateralRatio = (incentive * debtTokenPrice * WAD) /
            (price * _cToken.exchangeRateCached());
        uint256 amountAdjusted = (debtAmount * (10 ** _cToken.decimals())) /
            (10 ** _dToken.decimals());
        uint256 expectedLiquidatedTokens = (amountAdjusted *
            debtToCollateralRatio) / WAD;
        uint256 liqFee = (WAD * (10 * 1e14)) / liqBaseIncentive;
        expectedLiqAmount = debtAmount;

        if (expectedLiquidatedTokens > collateralAvailable) {
            expectedLiqAmount =
                (expectedLiqAmount * collateralAvailable) /
                expectedLiquidatedTokens;
        }

        expectedProtocolTokens = (collateralAvailable * liqFee) / WAD;

        console2.log(
            "expectedLiqAmount %s collateralAvailable %s expectedProtocolTokens %s",
            expectedLiqAmount,
            collateralAvailable,
            expectedProtocolTokens
        );
    }

    function _updateRoundData(
        MockV3Aggregator _agg,
        uint80 _roundId,
        int256 _price
    ) internal {
        _agg.updateRoundData(
            _roundId,
            _price,
            block.timestamp,
            block.timestamp
        );
    }

    function _runLiquidationChecks(
        address userToLiquidate,
        address liquidator,
        DToken _dToken,
        MockCTokenPrimitive _cToken,
        uint256 _expectedLiqAmount
    ) internal {
        DToken[] memory _dTokens = new DToken[](1);
        _dTokens[0] = _dToken;
        MockCTokenPrimitive[] memory _cTokens = new MockCTokenPrimitive[](1);
        _cTokens[0] = _cToken;
        address[] memory _users = new address[](2);
        _users[0] = userToLiquidate;
        _users[1] = liquidator;

        console2.log("\n pre liquidation asset check");
        _checkAssets(_dTokens, _cTokens, _users);
        console2.log("\n liquidate");
        uint256 snapshot = vm.snapshot();

        console2.log("lendTroller liquidateAccount");

        _liquidateAccount(userToLiquidate, liquidator);
        _checkAssets(_dTokens, _cTokens, _users);

        vm.revertTo(snapshot);

        console2.log("dTokens liquidateExact");

        _dTokenLiquidateExact(
            _dTokens[0],
            _cTokens[0],
            _expectedLiqAmount,
            userToLiquidate,
            liquidator
        );
        _checkAssets(_dTokens, _cTokens, _users);

        vm.revertTo(snapshot);

        console2.log("dTokens liquidate");
        _dTokenLiquidate(_dToken, _cToken, userToLiquidate, liquidator);
        _checkAssets(_dTokens, _cTokens, _users);
    }

    function _liquidateAllExact(
        DToken[] memory dTokens,
        MockCTokenPrimitive[] memory cTokens,
        address[] memory users
    ) internal {
        console2.log("_liquidateExact");
        for (uint256 i = 0; i < noOfUsersCollateral; i++) {
            for (uint256 j = 0; j < noOfCollateralTokens; j++) {
                if (!marketManager.flaggedForLiquidation(users[i])) {
                    console2.log(
                        "user %s not flagged for liquidation",
                        users[i]
                    );
                    continue;
                }
                if (cTokens[j].balanceOf(users[i]) == 0) {
                    continue;
                }
                for (uint256 k = 0; k < noOfDebtTokens; k++) {
                    if (
                        IERC20(dTokens[k].underlying()).balanceOf(users[i]) ==
                        0
                    ) {
                        continue;
                    }
                    console2.log(
                        "liquidate %s %s",
                        address(dTokens[k]),
                        address(cTokens[j])
                    );
                    _liquidate(dTokens[k], cTokens[j], users[i], true);
                    break;
                }
            }
        }
    }

    function _liquidateAllByDToken(
        DToken[] memory dTokens,
        MockCTokenPrimitive[] memory cTokens,
        address[] memory users
    ) internal {
        for (uint256 i = 0; i < noOfUsersCollateral; i++) {
            console2.log("user %s", users[i]);
            for (uint256 j = 0; j < noOfCollateralTokens; j++) {
                if (!marketManager.flaggedForLiquidation(users[i])) {
                    console2.log(
                        "user %s not flagged for liquidation",
                        users[i]
                    );
                    continue;
                }
                if (cTokens[j].balanceOf(users[i]) == 0) {
                    continue;
                }
                for (uint256 k = 0; k < noOfDebtTokens; k++) {
                    if (
                        IERC20(dTokens[k].underlying()).balanceOf(users[i]) ==
                        0
                    ) {
                        continue;
                    }
                    console2.log(
                        "liquidate %s %s",
                        address(dTokens[k]),
                        address(cTokens[j])
                    );
                    _liquidate(dTokens[k], cTokens[j], users[i], false);
                    break;
                }
            }
        }
    }

    function _liquidate(
        DToken _dToken,
        MockCTokenPrimitive _cToken,
        address _user,
        bool _exact
    ) internal {
        _dToken.accrueInterest();

        console2.log("\n expected liquidation");
        (uint256 expectedLiqAmount, , ) = _expectedLiquidation(
            _cToken.balanceOf(_user),
            _user,
            _dToken,
            _cToken
        );

        console2.log("\n check liquidation");
        _checkLiquidation(_user, _dToken, _cToken, expectedLiqAmount, _exact);

        console2.log("\n prep liquidation");
        _prepareLiquidation(liquidator, _dToken, expectedLiqAmount);

        console2.log("\n liquidate");
        if (_exact) {
            _dTokenLiquidateExact(
                _dToken,
                _cToken,
                expectedLiqAmount,
                _user,
                liquidator
            );
        } else {
            _dTokenLiquidate(_dToken, _cToken, _user, liquidator);
        }
    }

    function _liquidateAccount(
        address _account,
        address _liquidator
    ) internal {
        vm.prank(_liquidator);
        marketManager.liquidateAccount(_account);
    }

    function _dTokenLiquidateExact(
        DToken _dtoken,
        MockCTokenPrimitive _collateral,
        uint256 _expectedLiqAmount,
        address _account,
        address _liquidator
    ) internal {
        vm.prank(_liquidator);
        _dtoken.liquidateExact(
            _account,
            _expectedLiqAmount,
            IMToken(address(_collateral))
        );
    }

    function _dTokenLiquidate(
        DToken _dtoken,
        MockCTokenPrimitive _collateral,
        address _account,
        address _liquidator
    ) internal {
        vm.prank(_liquidator);
        _dtoken.liquidate(_account, IMToken(address(_collateral)));
    }

    function _getHypotheicalLiquidity(
        address account,
        address mTokenModified,
        uint256 redeemTokens, // in shares
        uint256 borrowAmount // in assets
    )
        internal
        view
        returns (uint256 overR, uint256 underR, uint256 overB, uint256 underB)
    {
        (overR, underR) = marketManager.hypotheticalLiquidityOf(
            account,
            address(mTokenModified),
            redeemTokens,
            0
        );

        (overB, underB) = marketManager.hypotheticalLiquidityOf(
            account,
            address(mTokenModified),
            0,
            borrowAmount
        );
        console2.log("redeem: over %s under %s", overR, underR);
        console2.log("borrow: over %s under %s", overB, underB);
    }

    function _getHypotheicalLiquidityAllUsers(
        address[] memory users,
        DToken[] memory dTokens,
        uint256 redeemTokens, // in shares
        uint256 borrowAmount // in assets
    ) internal view {
        for (uint256 i; i < noOfUsersCollateral; i++) {
            console2.log("user %s", users[i]);
            for (uint256 j; j < noOfDebtTokens; j++) {
                console2.log("debtToken %s", address(dTokens[j]));
                _getHypotheicalLiquidity(
                    users[i],
                    address(dTokens[j]),
                    redeemTokens,
                    borrowAmount
                );
            }
        }
    }

    function _checkAssets(
        DToken[] memory _dTokens,
        MockCTokenPrimitive[] memory _cTokens,
        address[] memory _users
    ) internal view returns (bool) {
        address user;
        for (uint256 i = 0; i < _users.length; i++) {
            user = _users[i];
            console2.log("\nuser %s", user);
            for (uint256 j = 0; j < _dTokens.length; j++) {
                console2.log("\ndtoken %s", j);
                _checkAssetDToken(_dTokens[j], user);
            }
            for (uint256 j = 0; j < _cTokens.length; j++) {
                console2.log("\nctoken %s", j);
                _checkAssetCToken(_cTokens[j], user);
            }
        }
        console2.log("\nliquidator %s", liquidator);
        for (uint256 j = 0; j < _dTokens.length; j++) {
            console2.log("\ndtoken %s", j);
            _checkAssetDToken(_dTokens[j], liquidator);
        }
        for (uint256 j = 0; j < _cTokens.length; j++) {
            console2.log("\nctoken %s", j);
            _checkAssetCToken(_cTokens[j], liquidator);
        }
        return true;
    }

    function _checkAssetDToken(
        DToken _dToken,
        address _user
    ) internal view returns (bool) {
        console2.log(
            "dToken %s balance %s",
            address(_dToken),
            _dToken.balanceOf(_user)
        );
        console2.log(
            "underlying %s balance %s",
            address(_dToken.underlying()),
            IERC20(_dToken.underlying()).balanceOf(_user)
        );
        return true;
    }

    function _checkAssetCToken(
        MockCTokenPrimitive _cToken,
        address _user
    ) internal view returns (bool) {
        console2.log(
            "cToken %s balance %s",
            address(_cToken),
            _cToken.balanceOf(_user)
        );
        console2.log(
            "underlying %s balance %s",
            address(_cToken.underlying()),
            IERC20(_cToken.underlying()).balanceOf(_user)
        );
        return true;
    }

    function _getUserAssets(
        address user
    )
        internal
        view
        returns (
            IMToken[] memory userAssets,
            uint256[] memory cTokenBalances,
            uint256[] memory dTokenBalances,
            uint256[] memory underlyingBalances
        )
    {
        userAssets = marketManager.assetsOf(user);
        cTokenBalances = new uint256[](noOfCollateralTokens);
        dTokenBalances = new uint256[](noOfDebtTokens);
        underlyingBalances = new uint256[](noOfDebtTokens);

        for (uint256 i = 0; i < userAssets.length; i++) {
            if (userAssets[i].isCToken()) {
                cTokenBalances[i] = userAssets[i].balanceOf(user);
            } else {
                dTokenBalances[i] = userAssets[i].balanceOf(user);
                underlyingBalances[i] = IERC20(userAssets[i].underlying())
                    .balanceOf(user);
            }
        }
    }
}
