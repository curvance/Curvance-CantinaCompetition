// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { GaugePool } from "contracts/gauge/GaugePool.sol";
import { IMToken } from "contracts/interfaces/market/IMToken.sol";

interface ILendtroller {

    function postCollateral(
        address account, 
        address mToken, 
        uint256 tokens
    ) external;

    function canMint(address mToken) external;

    function canRedeem(
        address mToken,
        address account,
        uint256 amount
    ) external;

    function canRedeemWithCollateralRemoval(
        address mToken,
        address account,
        uint256 balance, 
        uint256 amount,
        bool forceReduce
    ) external;

    function canBorrow(
        address mToken,
        address account,
        uint256 amount
    ) external;

    function canBorrowWithNotify(
        address mToken,
        address account,
        uint256 amount
    ) external;

    function canRepay(address mToken, address borrower) external;

    function canLiquidateWithExecution(
        address debtToken,
        address collateralToken,
        address account,
        uint256 amount,
        bool liquidateExact
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

    function reduceCollateralIfNecessary(
        address account, 
        address mToken, 
        uint256 balance, 
        uint256 amount
    ) external;

    function notifyBorrow(address mToken, address account) external;

    function isListed(address mToken) external view returns (bool);

    function hasPosition(
        address mToken,
        address user
    ) external view returns (bool);

    function assetsOf(
        address mToken
    ) external view returns (IMToken[] memory);

    function positionFolding() external view returns (address);

    function gaugePool() external view returns (GaugePool);

    function statusOf(
        address account
    ) external view returns (uint256, uint256, uint256);

    function solvencyOf(
        address account
    ) external view returns (uint256, uint256);
}
