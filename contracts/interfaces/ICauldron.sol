// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

interface ICauldron {
    function userCollateralShare(address account) external view returns (uint256);
}
