// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

interface IRariToken {
    function balanceOfUnderlying(address account) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function getCash() external view returns (uint256);

    function totalBorrows() external view returns (uint256);

    function totalReserves() external view returns (uint256);

    function totalAdminFees() external view returns (uint256);

    function totalFuseFees() external view returns (uint256);

    function exchangeRateCurrent() external view returns (uint256);
}
