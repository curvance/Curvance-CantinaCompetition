// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { BaseWrappedAggregator } from "./BaseWrappedAggregator.sol";
import { IChainlink } from "contracts/interfaces/external/chainlink/IChainlink.sol";
import { IWstETH } from "contracts/interfaces/external/wsteth/IWstETH.sol";

contract WstETHAggregator is BaseWrappedAggregator {
    address public wstETH;
    address public stETH;
    address public stETHAggregator;

    constructor(address _wstETH, address _stETH, address _stETHAggregator) {
        wstETH = _wstETH;
        stETH = _stETH;
        stETHAggregator = _stETHAggregator;
    }

    function underlyingAssetAggregator()
        public
        view
        override
        returns (address)
    {
        return stETHAggregator;
    }

    function getWrappedAssetWeight() public view override returns (uint256) {
        return IWstETH(wstETH).getStETHByWstETH(1e18);
    }
}
