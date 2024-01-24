// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CTokenCompounding } from "contracts/market/collateral/CTokenCompounding.sol";
import { DToken } from "contracts/market/collateral/DToken.sol";

import { WAD, DENOMINATOR } from "contracts/libraries/Constants.sol";
import { ERC165Checker } from "contracts/libraries/external/ERC165Checker.sol";

import { IMarketManager } from "contracts/interfaces/market/IMarketManager.sol";
import { IMToken } from "contracts/interfaces/market/IMToken.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IGaugePool } from "contracts/interfaces/IGaugePool.sol";
import { IFeeAccumulator } from "contracts/interfaces/IFeeAccumulator.sol";
import { IOracleRouter } from "contracts/interfaces/IOracleRouter.sol";
import { ICVELocker } from "contracts/interfaces/ICVELocker.sol";
import { IVeCVE } from "contracts/interfaces/IVeCVE.sol";

/// @notice An auxiliary contract for querying nuanced data 
///         inside the Curvance ecosystem.
contract CurvanceAuxiliaryData {

    /// STORAGE ///

    /// @notice Curvance DAO hub.
    ICentralRegistry public immutable centralRegistry;

    /// ERRORS ///

    error CurvanceAuxiliaryData__ParametersMisconfigured();
    error CurvanceAuxiliaryData__InvalidCentralRegistry();
    error CurvanceAuxiliaryData__Unauthorized();

    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_
    ) {
        if (
            !ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            )
        ) {
            revert CurvanceAuxiliaryData__InvalidCentralRegistry();
        }

        centralRegistry = centralRegistry_; 
    }

    /// EXTERNAL FUNCTIONS ///

    /// CHAIN-WIDE FUNCTIONS ///

    /// @notice Returns the current TVL inside Curvance.
    /// @return result The current TVL inside Curvance, in `WAD`.
    function getTotalTVL() external view returns (uint256 result) {
        address[] memory markets =  centralRegistry.marketManagers();
        uint256 numMarkets = markets.length;

        for (uint256 i; i < numMarkets; ) {
            result += getMarketTVL(markets[i++]);
        }
    }

    /// @notice Returns the current collateral TVL inside Curvance.
    /// @return result The current collateral TVL inside Curvance, in `WAD`.
    function getTotalCollateralTVL() external view returns (uint256 result) {
        address[] memory markets =  centralRegistry.marketManagers();
        uint256 numMarkets = markets.length;

        for (uint256 i; i < numMarkets; ) {
            result += getMarketCollateralTVL(markets[i++]);
        }
    }

    /// @notice Returns the current lending TVL inside Curvance.
    /// @return result The current lending TVL inside Curvance, in `WAD`.
    function getTotalLendingTVL() external view returns (uint256 result) {
        address[] memory markets =  centralRegistry.marketManagers();
        uint256 numMarkets = markets.length;

        for (uint256 i; i < numMarkets; ) {
            result += getMarketLendingTVL(markets[i++]);
        }
    }

    /// @notice Returns the current outstanding borrows inside Curvance.
    /// @return result The current outstanding borrows inside Curvance, in `WAD`.
    function getTotalBorrows() external view returns (uint256 result) {
        address[] memory markets =  centralRegistry.marketManagers();
        uint256 numMarkets = markets.length;

        for (uint256 i; i < numMarkets; ) {
            result += getMarketBorrows(markets[i++]);
        }
    }

    function getMarketManagers() external view returns (address[] memory) {
        return centralRegistry.marketManagers();
    }

    /// EXTERNAL ACCOUNT-SPECIFIC FUNCTIONS ///

    

    /// EXTERNAL TOKEN-SPECIFIC FUNCTIONS ///

    /// @notice Returns if an account has an active position in `token`, 
    ///         and any user balances or collateral posted in `token`.
    /// @param account The address of the account to check token data of.
    /// @param token The address of the market token.
    function getAccountTokenData(
        address account, 
        address token
    ) external view returns (bool, uint256, uint256) {
        IMarketManager marketManager = IMarketManager(IMToken(token).marketManager());
        return marketManager.tokenDataOf(account, token);
    }

    /// @notice Return the debt balance of `account` based on stored data.
    /// @param account The address whose debt balance should be calculated.
    /// @return `account`'s cached balance index for `token`.
    function getAccountDebtData(
        address account,
        address token
    ) external view returns (uint256) {
        return IMToken(token).debtBalanceCached(account);
    }

    /// @notice Calculates `token` utilization rate.
    /// @return The utilization rate, in `WAD`.
    function getUtilizationRate(
        address token
    ) external view returns (uint256) {
        return IMToken(token).utilizationRate();
    }

    /// @notice Returns `token` borrow interest rate per year.
    /// @return The borrow interest rate per year, in `WAD`.
    function borrowRatePerYear(
        address token
    ) external view returns (uint256) {
        return IMToken(token).getBorrowRatePerYear();
    }

    /// @notice Returns `token` supply interest rate per year.
    /// @return The supply interest rate per year, in `WAD`.
    function supplyRatePerYear(
        address token
    ) external view returns (uint256) {
        return IMToken(token).getSupplyRatePerYear();
    }

    function getBaseRewards(address token) external view returns (uint256) {

    }

    function getCVERewards(address token) external view returns (uint256) {

    }

    /// ORACLE ROUTER FUNCTIONS ///

    function getPrices(
        address[] calldata assets,
        bool[] calldata inUSD,
        bool[] calldata getLower
    ) external view returns (uint256[] memory, uint256[] memory) {
        return _getOracleRouter().getPrices(assets, inUSD, getLower);
    }

    function hasRewards(address user) external view returns (bool) {
        return _getCVELocker().hasRewardsToClaim(user);
    }

    /// PUBLIC FUNCTIONS ///

    /// MARKET-SPECIFIC FUNCTIONS ///

    /// @notice Returns the current TVL inside a Curvance market.
    /// @param market The market to query TVL for.
    /// @return result The current TVL inside `market`, in `WAD`.
    function getMarketTVL(
        address market
    ) public view returns (uint256 result) {
        address[] memory assets = getMarketAssets(market);
        uint256 numAssets = assets.length;
        address token;
        bool getLower;

        for (uint256 i; i < numAssets; ++i) {
            token = assets[i++];
            getLower = IMToken(token).isCToken() ? true : false;
            result += getTokenTVL(token, getLower);
        }
    }

    /// @notice Returns the current collateral TVL inside a Curvance market.
    /// @param market The market to query collateral TVL for.
    /// @return result The current collateral TVL inside `market`, in `WAD`.
    function getMarketCollateralTVL(
        address market
    ) public view returns (uint256 result) {
        address[] memory assets = getMarketCollateralAssets(market);
        uint256 numAssets = assets.length;

        for (uint256 i; i < numAssets; ++i) {
            result += getTokenTVL(assets[i++], true);
        }
    }

    /// @notice Returns the current lending TVL inside a Curvance market.
    /// @param market The market to query lending TVL for.
    /// @return result The current lending TVL inside `market`, in `WAD`.
    function getMarketLendingTVL(
        address market
    ) public view returns (uint256 result) {
        address[] memory assets = getMarketDebtAssets(market);
        uint256 numAssets = assets.length;

        for (uint256 i; i < numAssets; ) {
            result += getTokenTVL(assets[i++], false);
        }
    }

    /// @notice Returns the current outstanding borrows inside a Curvance market.
    /// @param market The market to query outstanding borrows for.
    /// @return result The current outstanding borrows inside `market`, in `WAD`.
    function getMarketBorrows(address market) public view returns (uint256 result) {
        address[] memory assets = getMarketDebtAssets(market);
        uint256 numAssets = assets.length;

        for (uint256 i; i < numAssets; ) {
            result += getTokenBorrows(assets[i++]);
        }
    }

    /// @notice Returns listed collateral assets inside `market`.
    /// @return The listed collateral assets.
    function getMarketCollateralAssets(
        address market
    ) public view returns (address[] memory) {
        address[] memory assets = getMarketAssets(market);
        uint256 numAssets = assets.length;

        address asset;
        uint256 numCollateralAssets;

        for (uint256 i; i < numAssets; ++i) {
            asset = assets[i];
            if (IMToken(asset).isCToken()){
                ++numCollateralAssets;
            }
        }

        address[] memory collateralAssets = new address[](numCollateralAssets);

        for (uint256 i; i < numAssets; ++i) {
            asset = assets[i];
            if (IMToken(asset).isCToken()){
                collateralAssets[i] = asset;
            }
        }

        return collateralAssets;
    }

    /// @notice Returns listed debt assets inside `market`.
    /// @return The listed debt assets.
    function getMarketDebtAssets(
        address market
    ) public view returns (address[] memory) {
        address[] memory assets = getMarketAssets(market);
        uint256 numAssets = assets.length;

        address asset;
        uint256 numDebtAssets;

        for (uint256 i; i < numAssets; ++i) {
            asset = assets[i];
            if (!IMToken(asset).isCToken()){
                ++numDebtAssets;
            }
        }

        address[] memory debtAssets = new address[](numDebtAssets);

        for (uint256 i; i < numAssets; ++i) {
            asset = assets[i];
            if (!IMToken(asset).isCToken()){
                debtAssets[i] = asset;
            }
        }

        return debtAssets;
    }

    /// @notice Returns all listed market assets inside `market`.
    /// @return The listed market assets.
    function getMarketAssets(
        address market
    ) public view returns (address[] memory) {
        return IMarketManager(market).tokensListed();
    }

    /// PUBLIC ACCOUNT-SPECIFIC FUNCTIONS ///

    function getUserLocks(
        address account
    ) public view returns (uint256[] memory, uint256[] memory) {
        return IVeCVE(centralRegistry.veCVE()).queryUserLocks(account);
    }

    function getUserLockLength(
        address account
    ) public view returns (uint256) {
        (uint256[] memory lockAmounts, ) = getUserLocks(account);
        return lockAmounts.length;
    }

    function getUserLockIndexExists(
        address account,
        uint256 lockIndex
    ) public view returns (bool) {
        return lockIndex >= getUserLockLength(account);
    }

    /// PUBLIC TOKEN-SPECIFIC FUNCTIONS ///

    /// @notice Returns the current TVL inside an MToken token.
    /// @param token The token to query TVL for.
    /// @return result The current TVL inside `token`, in `WAD`.
    function getTokenTVL(
        address token, 
        bool getLower
    ) public view returns (uint256 result) {
        // Get current shares total supply then query price and return.
        result = _getTokenPrice(token, getLower) * IMToken(token).totalSupply();
    }

    /// @notice Returns the outstanding underlying tokens borrowed from a DToken market.
    /// @param token The token to query outstanding borrows for.
    /// @return result The outstanding underlying tokens, in `WAD`.
    function getTokenBorrows(address token) public view returns (uint256 result) {
        IMToken mToken = IMToken(token);
        // Get outstanding borrows then query price and return.
        result = _getTokenPrice(mToken.underlying(), false) * mToken.totalBorrows();
    }

    /// INTERNAL FUNCTIONS ///

    function _getCVELocker() internal view returns (ICVELocker) {
        return ICVELocker(centralRegistry.cveLocker());
    }

    function _getOracleRouter() internal view returns (IOracleRouter) {
        return IOracleRouter(centralRegistry.oracleRouter());
    }

    function _getTokenPrice(
        address mToken, 
        bool getLower
    ) internal view returns (uint256 price) {
        uint256 errorCode;
        (price, errorCode) = _getOracleRouter().getPrice(mToken, true, getLower);
        // If we could not price the asset, bubble up a price of 0.
        if  (errorCode == 2) {
            price = 0;
            return price;
        }
    }

}
