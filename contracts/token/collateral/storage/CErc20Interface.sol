// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../../../interfaces/market/IEIP20NonStandard.sol";
import "./CErc20Storage.sol";
import "./CTokenInterface.sol";

abstract contract CErc20Interface is CErc20Storage {
    /*** User Interface ***/
    function mint(uint256 mintAmount) external virtual returns (bool);

    function redeem(uint256 redeemTokens) external virtual;

    function redeemUnderlying(uint256 redeemAmount) external virtual;

    function borrow(uint256 borrowAmount) external virtual;

    function repayBorrow(uint256 repayAmount) external virtual;

    function repayBorrowBehalf(address borrower, uint256 repayAmount)
        external
        virtual;

    function liquidateBorrow(
        address borrower,
        uint256 repayAmount,
        CTokenInterface cTokenCollateral
    ) external virtual;

    function sweepToken(IEIP20NonStandard token) external virtual;

    /*** Admin Functions ***/
    function _addReserves(uint256 addAmount) external virtual;
}
