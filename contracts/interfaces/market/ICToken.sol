// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";
import { InterestRateModel } from "contracts/market/interestRates/InterestRateModel.sol";

abstract contract ICToken {
    /// User Interface

    function transfer(
        address dst,
        uint256 amount
    ) external virtual returns (bool);

    function transferFrom(
        address src,
        address dst,
        uint256 amount
    ) external virtual returns (bool);

    function approve(
        address spender,
        uint256 amount
    ) external virtual returns (bool);

    function allowance(
        address owner,
        address spender
    ) external view virtual returns (uint256);

    function balanceOf(address owner) external view virtual returns (uint256);

    function balanceOfUnderlying(
        address owner
    ) external virtual returns (uint256);

    function getAccountSnapshot(
        address account
    ) external view virtual returns (uint256, uint256, uint256);

    function borrowRatePerBlock() external view virtual returns (uint256);

    function supplyRatePerBlock() external view virtual returns (uint256);

    function totalBorrowsCurrent() external virtual returns (uint256);

    function borrowBalanceCurrent(
        address account
    ) external virtual returns (uint256);

    function borrowBalanceStored(
        address account
    ) external view virtual returns (uint256);

    function exchangeRateCurrent() public virtual returns (uint256);

    function exchangeRateStored() public view virtual returns (uint256);

    function getCash() external view virtual returns (uint256);

    function accrueInterest() public virtual;

    function seize(
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) external virtual;

    /// Admin Functions

    function _setPendingAdmin(
        address payable newPendingAdmin
    ) external virtual;

    function _acceptAdmin() external virtual;

    function _setLendtroller(Lendtroller newLendtroller) public virtual;

    function _setReserveFactor(
        uint256 newReserveFactorMantissa
    ) external virtual;

    function _reduceReserves(uint256 reduceAmount) external virtual;

    function _setInterestRateModel(
        InterestRateModel newInterestRateModel
    ) external virtual;

    function accrualBlockTimestamp() external view virtual returns (uint256);
}
