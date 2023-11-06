// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

interface IWstETH {
    function getStETHByWstETH(
        uint256 _wstETHAmount
    ) external view returns (uint256);
}
