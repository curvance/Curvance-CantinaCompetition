// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CToken } from "contracts/token/collateral/CToken.sol";

interface ILendtroller {
    function enterMarkets(
        address[] calldata cTokens
    ) external virtual returns (uint256[] memory);

    function exitMarket(address cToken) external virtual;

    function mintAllowed(address cToken, address minter) external virtual;

    function redeemAllowed(
        address cToken,
        address redeemer,
        uint256 redeemTokens
    ) external virtual;

    function borrowAllowed(
        address cToken,
        address borrower,
        uint256 borrowAmount
    ) external virtual;

    function repayBorrowAllowed(
        address cToken,
        address borrower
    ) external virtual;

    function liquidateBorrowAllowed(
        address cTokenBorrowed,
        address cTokenCollateral,
        address borrower,
        uint256 repayAmount
    ) external virtual;

    function seizeAllowed(
        address cTokenCollateral,
        address cTokenBorrowed,
        address liquidator,
        address borrower
    ) external virtual;

    function transferAllowed(
        address cToken,
        address src,
        address dst,
        uint256 transferTokens
    ) external virtual;

    /*** Liquidity/Liquidation Calculations ***/

    function liquidateCalculateSeizeTokens(
        address cTokenBorrowed,
        address cTokenCollateral,
        uint256 repayAmount
    ) external view virtual returns (uint256);

    /** Query functions */
    function getIsMarkets(
        address cToken
    ) external view virtual returns (bool, uint256, bool);

    function getAccountMembership(
        address cToken,
        address user
    ) external view virtual returns (bool);

    function getAllMarkets() external view virtual returns (CToken[] memory);

    function getAccountAssets(
        address cToken
    ) external view virtual returns (CToken[] memory);
}
