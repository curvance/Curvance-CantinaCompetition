// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IYearnVault {
    function deposit(uint256 _amount) external returns (uint256);

    function withdraw(uint256 _shares) external;

    function pricePerShare() external view returns (uint256);

    function decimals() external view returns (uint256);

    function balanceOf(address _owner) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function totalAssets() external view returns (uint256);

    function totalDebt() external view returns (uint256);
}
