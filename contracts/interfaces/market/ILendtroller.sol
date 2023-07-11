// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CToken } from "contracts/market/collateral/CToken.sol";

interface ILendtroller {
    function enterMarkets(
        address[] calldata cTokens
    ) external returns (uint256[] memory);

    function exitMarket(address cToken) external;

    function mintAllowed(address cToken, address minter) external;

    function redeemAllowed(
        address cToken,
        address redeemer,
        uint256 redeemTokens
    ) external;

    function borrowAllowed(
        address cToken,
        address borrower,
        uint256 borrowAmount
    ) external;

    function repayBorrowAllowed(address cToken, address borrower) external;

    function liquidateBorrowAllowed(
        address cTokenBorrowed,
        address cTokenCollateral,
        address borrower,
        uint256 repayAmount
    ) external;

    function seizeAllowed(
        address cTokenCollateral,
        address cTokenBorrowed,
        address liquidator,
        address borrower
    ) external;

    function transferAllowed(
        address cToken,
        address src,
        address dst,
        uint256 transferTokens
    ) external;

    /*** Liquidity/Liquidation Calculations ***/

    function liquidateCalculateSeizeTokens(
        address cTokenBorrowed,
        address cTokenCollateral,
        uint256 repayAmount
    ) external view returns (uint256);

    /** Query functions */
    function getIsMarkets(
        address cToken
    ) external view returns (bool, uint256, bool);

    function getAccountMembership(
        address cToken,
        address user
    ) external view returns (bool);

    function getAllMarkets() external view returns (CToken[] memory);

    function getAccountAssets(
        address cToken
    ) external view returns (CToken[] memory);
}
