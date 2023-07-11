// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./IEIP20NonStandard.sol";
import "./ICToken.sol";

abstract contract ICErc20 {
    /// User Interface

    function mint(uint256 mintAmount) external virtual returns (bool);

    function redeem(uint256 redeemTokens) external virtual;

    function redeemUnderlying(uint256 redeemAmount) external virtual;

    function borrow(uint256 borrowAmount) external virtual;

    function repayBorrow(uint256 repayAmount) external virtual;

    function repayBorrowBehalf(
        address borrower,
        uint256 repayAmount
    ) external virtual;

    function liquidateBorrow(
        address borrower,
        uint256 repayAmount,
        ICToken cTokenCollateral
    ) external virtual;

    function sweepToken(IEIP20NonStandard token) external virtual;

    /// Admin Functions

    function _addReserves(uint256 addAmount) external virtual;
}
