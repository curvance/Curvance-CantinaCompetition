// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { GaugePool } from "contracts/gauge/GaugePool.sol";
import { IMToken } from "contracts/interfaces/market/IMToken.sol";

interface ILendtroller {
    function canMint(address mToken) external;

    function canRedeem(
        address mToken,
        address redeemer,
        uint256 amount
    ) external;

    function canBorrowWithNotify(
        address mToken,
        address borrower,
        uint256 amount
    ) external;

    function canBorrow(
        address mToken,
        address borrower,
        uint256 amount
    ) external;

    function canRepay(address mToken, address borrower) external;

    function canLiquidateExact(
        address mTokenBorrowed,
        address mTokenCollateral,
        address borrower,
        uint256 amount
    ) external returns (uint256, uint256);

    function canLiquidate(
        address mTokenBorrowed,
        address mTokenCollateral,
        address borrower
    ) external returns (uint256, uint256, uint256);

    function canSeize(
        address mTokenCollateral,
        address mTokenBorrowed
    ) external;

    function canTransfer(
        address mToken,
        address from,
        uint256 amount
    ) external;

    function notifyBorrow(address account) external;

    function isListed(address mToken) external view returns (bool);

    function getTokenData(
        address mToken
    ) external view returns (bool, uint256, uint256);

    function hasPosition(
        address mToken,
        address user
    ) external view returns (bool);

    function getAccountAssets(
        address mToken
    ) external view returns (IMToken[] memory);

    function positionFolding() external view returns (address);

    function gaugePool() external view returns (GaugePool);

    function getStatus(
        address account
    ) external view returns (uint256, uint256, uint256);
}
