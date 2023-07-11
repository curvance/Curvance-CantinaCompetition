// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "contracts/market/interestRates/InterestRateModel.sol";
import { ILendtroller } from "contracts/interfaces/market/ILendtroller.sol";

interface ICToken {
    function isCToken() external view returns (bool);

    function symbol() external view returns (string memory);

    function totalBorrows() external view returns (uint256);

    function lendtroller() external view returns (ILendtroller);

    function transfer(address dst, uint256 amount) external returns (bool);

    function transferFrom(
        address src,
        address dst,
        uint256 amount
    ) external returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function balanceOfUnderlying(address owner) external returns (uint256);

    function getAccountSnapshot(
        address account
    ) external view returns (uint256, uint256, uint256);

    function borrowRatePerBlock() external view returns (uint256);

    function supplyRatePerBlock() external view returns (uint256);

    function totalBorrowsCurrent() external returns (uint256);

    function borrowBalanceCurrent(address account) external returns (uint256);

    function borrowBalanceStored(
        address account
    ) external view returns (uint256);

    function exchangeRateCurrent() external returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function getCash() external view returns (uint256);

    function accrueInterest() external;

    function seize(
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) external;

    /// Admin Functions

    function _setPendingAdmin(address payable newPendingAdmin) external;

    function _acceptAdmin() external;

    function _setLendtroller(ILendtroller newLendtroller) external;

    function _setReserveFactor(uint256 newReserveFactorMantissa) external;

    function _reduceReserves(uint256 reduceAmount) external;

    function _setInterestRateModel(
        InterestRateModel newInterestRateModel
    ) external;

    function accrualBlockTimestamp() external view returns (uint256);
}
