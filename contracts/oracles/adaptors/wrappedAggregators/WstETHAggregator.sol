// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { BaseWrappedAggregator } from "./BaseWrappedAggregator.sol";
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

    /// @notice Returns the underlying aggregator address.
    function underlyingAssetAggregator()
        public
        view
        override
        returns (address)
    {
        return stETHAggregator;
    }

    /// @notice Returns the current exchange rate between the wrapped asset
    ///         and the underlying aggregator, in `WAD`.
    function getWrappedAssetWeight() public view override returns (int256) {
        // get pricing in 1e18 format directly to minimize calculations.
        return SafeCast.toInt256(IWstETH(wstETH).getStETHByWstETH(1e18));
    }
}
