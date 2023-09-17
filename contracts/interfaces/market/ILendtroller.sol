// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IMToken } from "contracts/interfaces/market/IMToken.sol";

interface ILendtroller {
    function mintAllowed(address mToken, address minter) external;

    function redeemAllowed(
        address mToken,
        address redeemer,
        uint256 redeemTokens
    ) external;

    function borrowAllowedWithNotify(
        address mToken,
        address borrower,
        uint256 borrowAmount
    ) external;

    function borrowAllowed(
        address mToken,
        address borrower,
        uint256 borrowAmount
    ) external;

    function repayAllowed(address mToken, address borrower) external;

    function liquidateAllowed(
        address mTokenBorrowed,
        address mTokenCollateral,
        address borrower,
        uint256 repayAmount
    ) external;

    function seizeAllowed(
        address mTokenCollateral,
        address mTokenBorrowed,
        address liquidator,
        address borrower
    ) external;

    function transferAllowed(
        address mToken,
        address src,
        address dst,
        uint256 transferTokens
    ) external;

    function notifyAccountBorrow(address account) external;

    function calculateLiquidatedTokens(
        address mTokenBorrowed,
        address mTokenCollateral,
        uint256 repayAmount
    ) external view returns (uint256);

    function isListed(
        address mToken
    ) external view returns (bool);

    function getMarketTokenData(
        address mToken
    ) external view returns (bool, uint256, uint256);

    function getAccountMembership(
        address mToken,
        address user
    ) external view returns (bool);

    function getAccountAssets(
        address mToken
    ) external view returns (IMToken[] memory);

    function positionFolding() external view returns (address);

    function gaugePool() external view returns (address);

    function getAccountPosition(
        address account
    ) external view returns (uint256, uint256, uint256);
}
