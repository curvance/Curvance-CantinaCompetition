// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./IEIP20NonStandard.sol";
import "./ICToken.sol";

interface ICErc20 {
    ////////// Errors //////////

    error InvalidUnderlying();
    error TransferFailure();
    error ActionFailure();

    /// User Interface

    function mint(uint256 mintAmount) external returns (bool);

    function redeem(uint256 redeemTokens) external;

    function redeemUnderlying(uint256 redeemAmount) external;

    function borrow(uint256 borrowAmount) external;

    function repayBorrow(uint256 repayAmount) external;

    function repayBorrowBehalf(address borrower, uint256 repayAmount) external;

    function liquidateBorrow(
        address borrower,
        uint256 repayAmount,
        ICToken cTokenCollateral
    ) external;

    function sweepToken(IEIP20NonStandard token) external;

    /// Admin Functions

    function _addReserves(uint256 addAmount) external;
}
